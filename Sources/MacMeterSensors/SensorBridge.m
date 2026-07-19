#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <math.h>
#import "MacMeterSensors.h"

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

#define MMIOHIDEventFieldBase(type) (type << 16)
#define MMIOHIDEventTypeTemperature 15

#define MMSMCKernelIndex 2
#define MMSMCCommandReadBytes 5
#define MMSMCCommandReadIndex 8
#define MMSMCCommandReadKeyInfo 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    uint16_t release;
} MMSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} MMSMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} MMSMCKeyInfo;

typedef struct {
    uint32_t key;
    MMSMCVersion version;
    MMSMCPLimitData pLimitData;
    MMSMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    char bytes[32];
} MMSMCKeyData;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

static void MMRecordTemperature(
    NSString *product,
    double value,
    NSMutableDictionary<NSString *, NSNumber *> *socSensors
) {
    BOOL isNamedSoCSensor = [product hasPrefix:@"SOC MTR Temp"];
    if (!isNamedSoCSensor || !isfinite(value) || value < 0.0 || value > 110.0) { return; }
    NSNumber *existing = socSensors[product];
    if (existing == nil || value > existing.doubleValue) {
        socSensors[product] = @(value);
    }
}

static double MMSelectRecordedTemperature(
    NSDictionary<NSString *, NSNumber *> *socSensors,
    int32_t *sensorCount
) {
    double hottest = -INFINITY;
    for (NSNumber *value in socSensors.allValues) {
        hottest = fmax(hottest, value.doubleValue);
    }
    int32_t count = (int32_t)socSensors.count;
    if (sensorCount != NULL) { *sensorCount = count; }
    return count > 0 ? hottest : NAN;
}

double MMSelectSoCTemperature(const char **sensorNames, const double *values, int32_t inputCount, int32_t *sensorCount) {
    if (sensorCount != NULL) { *sensorCount = 0; }
    if (sensorNames == NULL || values == NULL || inputCount <= 0) { return NAN; }
    NSMutableDictionary<NSString *, NSNumber *> *socSensors = [NSMutableDictionary dictionary];
    for (int32_t index = 0; index < inputCount; index++) {
        if (sensorNames[index] == NULL) { continue; }
        NSString *product = [NSString stringWithUTF8String:sensorNames[index]];
        if (product != nil) { MMRecordTemperature(product, values[index], socSensors); }
    }
    return MMSelectRecordedTemperature(socSensors, sensorCount);
}

static uint32_t MMFourCC(const char *value) {
    return ((uint32_t)(uint8_t)value[0] << 24) |
        ((uint32_t)(uint8_t)value[1] << 16) |
        ((uint32_t)(uint8_t)value[2] << 8) |
        (uint32_t)(uint8_t)value[3];
}

static NSString *MMFourCCString(uint32_t value) {
    char name[5] = {
        (char)((value >> 24) & 0xff),
        (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff),
        (char)(value & 0xff),
        '\0'
    };
    return [NSString stringWithCString:name encoding:NSASCIIStringEncoding];
}

static BOOL MMIsSMCSoCTemperatureName(NSString *name) {
    return [name hasPrefix:@"Tp"] || [name hasPrefix:@"Te"] ||
        [name hasPrefix:@"Tg"] || [name isEqualToString:@"TCMz"];
}

static void MMRecordSMCTemperature(
    NSString *name,
    double value,
    NSMutableDictionary<NSString *, NSNumber *> *socSensors
) {
    if (!MMIsSMCSoCTemperatureName(name) || !isfinite(value) || value <= 0.0 || value > 110.0) { return; }
    NSNumber *existing = socSensors[name];
    if (existing == nil || value > existing.doubleValue) {
        socSensors[name] = @(value);
    }
}

double MMSelectSMCSoCTemperature(
    const char **sensorNames,
    const double *values,
    int32_t inputCount,
    int32_t *sensorCount
) {
    if (sensorCount != NULL) { *sensorCount = 0; }
    if (sensorNames == NULL || values == NULL || inputCount <= 0) { return NAN; }
    NSMutableDictionary<NSString *, NSNumber *> *socSensors = [NSMutableDictionary dictionary];
    for (int32_t index = 0; index < inputCount; index++) {
        if (sensorNames[index] == NULL) { continue; }
        NSString *name = [NSString stringWithUTF8String:sensorNames[index]];
        if (name != nil) { MMRecordSMCTemperature(name, values[index], socSensors); }
    }
    return MMSelectRecordedTemperature(socSensors, sensorCount);
}

static BOOL MMSMCCall(io_connect_t connection, MMSMCKeyData *input, MMSMCKeyData *output) {
    size_t outputSize = sizeof(MMSMCKeyData);
    memset(output, 0, sizeof(MMSMCKeyData));
    kern_return_t result = IOConnectCallStructMethod(
        connection,
        MMSMCKernelIndex,
        input,
        sizeof(MMSMCKeyData),
        output,
        &outputSize
    );
    return result == KERN_SUCCESS && output->result == 0;
}

static BOOL MMSMCReadKeyInfo(io_connect_t connection, uint32_t key, MMSMCKeyInfo *keyInfo) {
    MMSMCKeyData input = {0};
    MMSMCKeyData output = {0};
    input.key = key;
    input.data8 = MMSMCCommandReadKeyInfo;
    if (!MMSMCCall(connection, &input, &output)) { return NO; }
    *keyInfo = output.keyInfo;
    return YES;
}

static BOOL MMSMCReadKey(io_connect_t connection, uint32_t key, MMSMCKeyData *value) {
    MMSMCKeyInfo keyInfo = {0};
    if (!MMSMCReadKeyInfo(connection, key, &keyInfo) || keyInfo.dataSize > sizeof(value->bytes)) { return NO; }
    MMSMCKeyData input = {0};
    MMSMCKeyData output = {0};
    input.key = key;
    input.keyInfo.dataSize = keyInfo.dataSize;
    input.data8 = MMSMCCommandReadBytes;
    if (!MMSMCCall(connection, &input, &output)) { return NO; }
    output.keyInfo = keyInfo;
    *value = output;
    return YES;
}

static BOOL MMSMCReadCachedKey(
    io_connect_t connection,
    uint32_t key,
    uint32_t dataSize,
    MMSMCKeyData *value
) {
    if (dataSize > sizeof(value->bytes)) { return NO; }
    MMSMCKeyData input = {0};
    MMSMCKeyData output = {0};
    input.key = key;
    input.keyInfo.dataSize = dataSize;
    input.data8 = MMSMCCommandReadBytes;
    if (!MMSMCCall(connection, &input, &output)) { return NO; }
    *value = output;
    return YES;
}

static io_connect_t MMSMCOpen(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) { return IO_OBJECT_NULL; }
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : IO_OBJECT_NULL;
}

static NSArray<NSDictionary<NSString *, id> *> *MMSMCDiscoverSoCKeys(io_connect_t connection) {
    MMSMCKeyData countValue = {0};
    if (!MMSMCReadKey(connection, MMFourCC("#KEY"), &countValue) || countValue.keyInfo.dataSize < 4) {
        return @[];
    }
    const uint8_t *countBytes = (const uint8_t *)countValue.bytes;
    uint32_t keyCount = ((uint32_t)countBytes[0] << 24) |
        ((uint32_t)countBytes[1] << 16) |
        ((uint32_t)countBytes[2] << 8) |
        (uint32_t)countBytes[3];
    NSMutableArray<NSDictionary<NSString *, id> *> *keys = [NSMutableArray array];
    const uint32_t floatType = MMFourCC("flt ");
    for (uint32_t index = 0; index < keyCount; index++) {
        MMSMCKeyData input = {0};
        MMSMCKeyData output = {0};
        input.data8 = MMSMCCommandReadIndex;
        input.data32 = index;
        if (!MMSMCCall(connection, &input, &output) || output.key == 0) { continue; }
        NSString *name = MMFourCCString(output.key);
        if (name == nil || !MMIsSMCSoCTemperatureName(name)) { continue; }
        MMSMCKeyInfo keyInfo = {0};
        if (!MMSMCReadKeyInfo(connection, output.key, &keyInfo) ||
            keyInfo.dataType != floatType || keyInfo.dataSize < sizeof(float)) { continue; }
        [keys addObject:@{@"key": @(output.key), @"size": @(keyInfo.dataSize), @"name": name}];
    }
    return keys;
}

static NSObject *MMSMCLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [[NSObject alloc] init]; });
    return lock;
}

static double MMHottestSMCSoCTemperature(int32_t *sensorCount) {
    if (sensorCount != NULL) { *sensorCount = 0; }
    static io_connect_t connection = IO_OBJECT_NULL;
    static NSArray<NSDictionary<NSString *, id> *> *keys;
    @synchronized (MMSMCLock()) {
        if (connection == IO_OBJECT_NULL) {
            connection = MMSMCOpen();
            if (connection == IO_OBJECT_NULL) { return NAN; }
            keys = MMSMCDiscoverSoCKeys(connection);
            if (keys.count == 0) {
                IOServiceClose(connection);
                connection = IO_OBJECT_NULL;
                return NAN;
            }
        }

        NSMutableDictionary<NSString *, NSNumber *> *socSensors = [NSMutableDictionary dictionary];
        for (NSDictionary<NSString *, id> *entry in keys) {
            MMSMCKeyData value = {0};
            NSNumber *key = entry[@"key"];
            NSNumber *size = entry[@"size"];
            NSString *name = entry[@"name"];
            if (![key isKindOfClass:NSNumber.class] || ![size isKindOfClass:NSNumber.class] ||
                ![name isKindOfClass:NSString.class] ||
                !MMSMCReadCachedKey(connection, key.unsignedIntValue, size.unsignedIntValue, &value)) { continue; }
            float reading = NAN;
            memcpy(&reading, value.bytes, sizeof(float));
            MMRecordSMCTemperature(name, (double)reading, socSensors);
        }
        double hottest = MMSelectRecordedTemperature(socSensors, sensorCount);
        if (!isfinite(hottest)) {
            // A sleep/wake transition can invalidate an AppleSMC user client.
            // Drop it so the next refresh reopens and re-enumerates fresh keys.
            IOServiceClose(connection);
            connection = IO_OBJECT_NULL;
            keys = nil;
        }
        return hottest;
    }
}

double MMHottestSoCTemperature(int32_t *sensorCount) {
    if (sensorCount != NULL) { *sensorCount = 0; }
    NSDictionary *matching = @{ @"PrimaryUsagePage": @0xff00, @"PrimaryUsage": @0x0005 };
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) { return MMHottestSMCSoCTemperature(sensorCount); }
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return MMHottestSMCSoCTemperature(sensorCount);
    }

    NSMutableDictionary<NSString *, NSNumber *> *socSensors = [NSMutableDictionary dictionary];
    CFIndex serviceCount = CFArrayGetCount(services);
    for (CFIndex index = 0; index < serviceCount; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        CFTypeRef rawProduct = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        NSString *product = CFBridgingRelease(rawProduct);
        BOOL isNamedSoCSensor = [product hasPrefix:@"SOC MTR Temp"];
        if (!isNamedSoCSensor) { continue; }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, MMIOHIDEventTypeTemperature, 0, 0);
        if (event == NULL) { continue; }
        double value = IOHIDEventGetFloatValue(event, MMIOHIDEventFieldBase(MMIOHIDEventTypeTemperature));
        CFRelease(event);
        MMRecordTemperature(product, value, socSensors);
    }

    CFRelease(services);
    CFRelease(client);
    double hottest = MMSelectRecordedTemperature(socSensors, sensorCount);
    return isfinite(hottest) ? hottest : MMHottestSMCSoCTemperature(sensorCount);
}
