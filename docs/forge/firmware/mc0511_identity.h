#pragma once
#include <ctype.h>
#include <string.h>

// Match the padded KG1 ID without allocating/freeing an Arduino String in
// per-sector and per-loop paths. Preserve String::trim() whitespace semantics.
inline bool mc0511_id_matches(const char *id) {
  while (*id && isspace(static_cast<unsigned char>(*id))) ++id;
  if (strncmp(id, "mc0511", 6) != 0) return false;
  id += 6;
  while (*id && isspace(static_cast<unsigned char>(*id))) ++id;
  return *id == '\0';
}
