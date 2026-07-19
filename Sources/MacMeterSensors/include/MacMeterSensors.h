#pragma once

#include <stdint.h>

double MMHottestSoCTemperature(int32_t *sensorCount);
double MMSelectSoCTemperature(const char **sensorNames, const double *values, int32_t inputCount, int32_t *sensorCount);
double MMSelectSMCSoCTemperature(const char **sensorNames, const double *values, int32_t inputCount, int32_t *sensorCount);
