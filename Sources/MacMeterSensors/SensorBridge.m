#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <math.h>
#import "MacMeterSensors.h"

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

#define MMIOHIDEventFieldBase(type) (type << 16)
#define MMIOHIDEventTypeTemperature 15

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

static void MMRecordTemperature(
    NSString *product,
    double value,
    NSMutableDictionary<NSString *, NSNumber *> *socSensors,
    NSMutableDictionary<NSString *, NSNumber *> *pmuDieSensors
) {
    BOOL isNamedSoCSensor = [product hasPrefix:@"SOC MTR Temp"];
    BOOL isPMUDieSensor = [product hasPrefix:@"PMU tdie"];
    if ((!isNamedSoCSensor && !isPMUDieSensor) || !isfinite(value) || value < 0.0 || value > 110.0) { return; }
    NSMutableDictionary<NSString *, NSNumber *> *destination = isNamedSoCSensor ? socSensors : pmuDieSensors;
    NSNumber *existing = destination[product];
    if (existing == nil || value > existing.doubleValue) {
        destination[product] = @(value);
    }
}

static double MMSelectRecordedTemperature(
    NSDictionary<NSString *, NSNumber *> *socSensors,
    NSDictionary<NSString *, NSNumber *> *pmuDieSensors,
    int32_t *sensorCount
) {
    NSDictionary<NSString *, NSNumber *> *selected = socSensors.count > 0 ? socSensors : pmuDieSensors;
    double hottest = -INFINITY;
    for (NSNumber *value in selected.allValues) {
        hottest = fmax(hottest, value.doubleValue);
    }
    int32_t count = (int32_t)selected.count;
    if (sensorCount != NULL) { *sensorCount = count; }
    return count > 0 ? hottest : NAN;
}

double MMSelectSoCTemperature(const char **sensorNames, const double *values, int32_t inputCount, int32_t *sensorCount) {
    if (sensorCount != NULL) { *sensorCount = 0; }
    if (sensorNames == NULL || values == NULL || inputCount <= 0) { return NAN; }
    NSMutableDictionary<NSString *, NSNumber *> *socSensors = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *pmuDieSensors = [NSMutableDictionary dictionary];
    for (int32_t index = 0; index < inputCount; index++) {
        if (sensorNames[index] == NULL) { continue; }
        NSString *product = [NSString stringWithUTF8String:sensorNames[index]];
        if (product != nil) { MMRecordTemperature(product, values[index], socSensors, pmuDieSensors); }
    }
    return MMSelectRecordedTemperature(socSensors, pmuDieSensors, sensorCount);
}

double MMHottestSoCTemperature(int32_t *sensorCount) {
    if (sensorCount != NULL) { *sensorCount = 0; }
    NSDictionary *matching = @{ @"PrimaryUsagePage": @0xff00, @"PrimaryUsage": @0x0005 };
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) { return NAN; }
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return NAN;
    }

    NSMutableDictionary<NSString *, NSNumber *> *socSensors = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *pmuDieSensors = [NSMutableDictionary dictionary];
    CFIndex serviceCount = CFArrayGetCount(services);
    for (CFIndex index = 0; index < serviceCount; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        CFTypeRef rawProduct = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        NSString *product = CFBridgingRelease(rawProduct);
        BOOL isNamedSoCSensor = [product hasPrefix:@"SOC MTR Temp"];
        BOOL isPMUDieSensor = [product hasPrefix:@"PMU tdie"];
        if (!isNamedSoCSensor && !isPMUDieSensor) { continue; }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, MMIOHIDEventTypeTemperature, 0, 0);
        if (event == NULL) { continue; }
        double value = IOHIDEventGetFloatValue(event, MMIOHIDEventFieldBase(MMIOHIDEventTypeTemperature));
        CFRelease(event);
        MMRecordTemperature(product, value, socSensors, pmuDieSensors);
    }

    CFRelease(services);
    CFRelease(client);
    return MMSelectRecordedTemperature(socSensors, pmuDieSensors, sensorCount);
}
