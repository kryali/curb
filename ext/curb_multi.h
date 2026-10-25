/* curb_multi.h - Curl easy mode
 * Copyright (c)2008 Todd A. Fisher.
 * Licensed under the Ruby License. See LICENSE for details.
 *
 * $Id$
 */
#ifndef __CURB_MULTI_H
#define __CURB_MULTI_H

#include "curb.h"
#include <curl/multi.h>

struct st_table;

typedef struct {
  int active;
  int running;
  char closed;
  char perform_active;
  VALUE perform_thread; /* Owner while a drive loop may release the GVL. */
  char callback_active;
  char allow_close_during_perform;
  CURLM *handle;
  struct st_table *attached;
  /* Bumped on every add and stamped onto the easy (multi_attachment_generation),
   * so "attached after point X" is a comparison instead of a table snapshot.
   * Monotonic for the object's lifetime; never reset. */
  unsigned long attachment_sequence;
} ruby_curl_multi;

extern VALUE cCurlMulti;
extern const rb_data_type_t ruby_curl_multi_data_type;

void init_curb_multi();
int rb_curl_multi_easy_performing(void *rbce_ptr);
void rb_curl_multi_check_easy_thread(void *rbce_ptr);
void rb_curl_multi_remove_request_reference(VALUE self, VALUE easy);
void rb_curl_multi_forget_easy(ruby_curl_multi *rbcm, void *rbce_ptr);
CURLMcode rb_curl_multi_detach_easy(ruby_curl_multi *rbcm, void *rbce_ptr);


#endif
