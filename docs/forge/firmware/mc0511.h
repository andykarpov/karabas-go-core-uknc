#pragma once
#include <stddef.h>
#include <stdint.h>
bool mc0511_active();
#include "mc0511_media.h"
void mc0511_sanitize_slot(uint8_t slot);
void mc0511_geometry(uint8_t slot);
void mc0511_run_sav();
void mc0511_rtc_seed();


void mc0511_register_handlers();
const char *mc0511_status_text();

void mc0511_ui_tick();
