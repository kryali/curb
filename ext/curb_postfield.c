/* curb_postfield.c - Field class for POST method
 * Copyright (c)2006 Ross Bamford. 
 * Licensed under the Ruby License. See LICENSE for details.
 * 
 * $Id: curb_postfield.c 30 2006-12-09 12:30:24Z roscopeco $
 */
#include "curb_postfield.h"
#include "curb_errors.h"

extern VALUE mCurl;

static VALUE idCall;

#ifdef RDOC_NEVER_DEFINED
  mCurl = rb_define_module("Curl");
#endif

VALUE cCurlPostField;


/* ================= APPEND FORM FUNC ================ */

/* Keep private, immutable strings alive until the request frees its form.
 * Snapshot each value before invoking any further user-defined coercions. */
static VALUE form_string_snapshot(VALUE value, ruby_curl_form_string **strings) {
  VALUE snapshot;
  ruby_curl_form_string *entry;
  StringValue(value);
  snapshot = rb_str_new(RSTRING_PTR(value), RSTRING_LEN(value));
  rb_obj_freeze(snapshot);
  entry = ALLOC(ruby_curl_form_string);
  entry->string = snapshot;
  entry->next = *strings;
  *strings = entry;
  /* Register individually to pin embedded string buffers during compaction. */
  rb_gc_register_address(&entry->string);
  return snapshot;
}

void free_form_strings(ruby_curl_form_string *strings) {
  while (strings) {
    ruby_curl_form_string *next = strings->next;
    rb_gc_unregister_address(&strings->string);
    xfree(strings);
    strings = next;
  }
}

void append_to_form(VALUE self,
                    struct curl_httppost **first,
                    struct curl_httppost **last,
                    ruby_curl_form_string **strings) {
  ruby_curl_postfield *rbcpf;
  CURLFORMcode result = -1;
  VALUE name, content = Qnil, remote = Qnil, local = Qnil, type = Qnil;
  int is_file;
  struct curl_forms form[8];
  int n = 0;

  TypedData_Get_Struct(self, ruby_curl_postfield, &ruby_curl_postfield_data_type, rbcpf);
  if (NIL_P(rbcpf->name)) {
    rb_raise(eCurlErrInvalidPostField, "Cannot post unnamed field");
  }
  is_file = !NIL_P(rbcpf->local_file) || !NIL_P(rbcpf->remote_file);
  if (!NIL_P(rbcpf->content_proc)) {
    rbcpf->buffer_str = rb_funcall(rbcpf->content_proc, idCall, 1, self);
    StringValue(rbcpf->buffer_str);
    content = form_string_snapshot(rbcpf->buffer_str, strings);
  } else if (!NIL_P(rbcpf->content)) {
    StringValue(rbcpf->content);
    content = form_string_snapshot(rbcpf->content, strings);
  }

  name = form_string_snapshot(rbcpf->name, strings);
  if (is_file) {
    if (!NIL_P(content)) {
      if (NIL_P(rbcpf->remote_file)) {
        rb_raise(eCurlErrInvalidPostField, "Cannot post file upload field with no filename");
      }
    } else if (!NIL_P(rbcpf->local_file)) {
      local = form_string_snapshot(rbcpf->local_file, strings);
      if (NIL_P(rbcpf->remote_file)) rbcpf->remote_file = rbcpf->local_file;
    } else {
      rb_raise(eCurlErrInvalidPostField, "Cannot post file upload field with no data");
    }
    remote = form_string_snapshot(rbcpf->remote_file, strings);
  } else if (NIL_P(content)) {
    rb_raise(eCurlErrInvalidPostField, "Cannot post content field with no data");
  }
  if (!NIL_P(rbcpf->content_type)) {
    type = form_string_snapshot(rbcpf->content_type, strings);
  }

  /* No Ruby calls after extracting pointers. The request owns all snapshots;
   * libcurl copies names/ordinary contents and borrows only file buffers. */
  form[n].option = CURLFORM_COPYNAME;
  form[n++].value = RSTRING_PTR(name);
  if (is_file) {
    form[n].option = NIL_P(content) ? CURLFORM_FILE : CURLFORM_BUFFER;
    form[n++].value = RSTRING_PTR(NIL_P(content) ? local : remote);
    if (NIL_P(content)) {
      form[n].option = CURLFORM_FILENAME;
      form[n++].value = RSTRING_PTR(remote);
    }
  }
  if (!NIL_P(type)) {
    form[n].option = CURLFORM_CONTENTTYPE;
    form[n++].value = RSTRING_PTR(type);
  }
  form[n].option = CURLFORM_END;
  form[n].value = NULL;

  if (NIL_P(content)) {
    result = curl_formadd(first, last, CURLFORM_ARRAY, form, CURLFORM_END);
  } else {
    result = curl_formadd(first, last, CURLFORM_ARRAY, form,
                         is_file ? CURLFORM_BUFFERPTR : CURLFORM_COPYCONTENTS,
                         RSTRING_PTR(content),
                         is_file ? CURLFORM_BUFFERLENGTH : CURLFORM_CONTENTSLENGTH,
                         RSTRING_LEN(content), CURLFORM_END);
  }

  if (result != 0) {
    const char *reason = NULL;
    
    switch (result) {
      case CURL_FORMADD_MEMORY:
        reason = "Memory allocation failed";
        break;
      case CURL_FORMADD_OPTION_TWICE:
        reason = "Duplicate option";
        break;
      case CURL_FORMADD_NULL:
        reason = "Unexpected NULL string";
        break;
      case CURL_FORMADD_UNKNOWN_OPTION:
        reason = "Unknown option";
        break;
      case CURL_FORMADD_INCOMPLETE:
        reason = "Incomplete form data";
        break;
      case CURL_FORMADD_ILLEGAL_ARRAY:
        reason = "Illegal array [BINDING BUG]";
        break;
      case CURL_FORMADD_DISABLED:
        reason = "Installed libcurl cannot support requested feature(s)";
        break;
      default:
        reason = "Unknown error";        
    }
    
    rb_raise(eCurlErrInvalidPostField, "Failed to add field (%s)", reason);
  }
}


/* ================== MARK/FREE FUNC ==================*/
static void curl_postfield_mark(void *ptr) {
  ruby_curl_postfield *rbcpf = (ruby_curl_postfield *)ptr;
  if (rbcpf) {
    rb_gc_mark(rbcpf->name);
    rb_gc_mark(rbcpf->content);
    rb_gc_mark(rbcpf->content_type);
    rb_gc_mark(rbcpf->content_proc);
    rb_gc_mark(rbcpf->local_file);
    rb_gc_mark(rbcpf->remote_file);
    rb_gc_mark(rbcpf->buffer_str);
  }
}

static void curl_postfield_free(void *ptr) {
  if (ptr) free(ptr);
}

static size_t curl_postfield_memsize(const void *ptr) {
  (void)ptr;
  return sizeof(ruby_curl_postfield);
}

const rb_data_type_t ruby_curl_postfield_data_type = {
  "Curl::PostField",
  {
    curl_postfield_mark,
    curl_postfield_free,
    curl_postfield_memsize,
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
    NULL, /* compact */
#endif
  },
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
  NULL, NULL, /* parent, data */
  RUBY_TYPED_FREE_IMMEDIATELY
#endif
};


/* ================= ALLOC METHODS ====================*/

/*
 * call-seq:
 *   Curl::PostField.content(name, content) => #<Curl::PostField...>
 *   Curl::PostField.content(name, content, content_type = nil) => #<Curl::PostField...>
 *   Curl::PostField.content(name, content_type = nil) { |field| ... } => #<Curl::PostField...>
 * 
 * Create a new Curl::PostField, supplying the field name, content,
 * and, optionally, Content-type (curl will attempt to determine this if
 * not specified).
 * 
 * The block form allows a block to supply the content for this field, called
 * during the perform. The block should return a ruby string with the field
 * data.
 */
static VALUE ruby_curl_postfield_new_content(int argc, VALUE *argv, VALUE klass) {
  VALUE self;
  ruby_curl_postfield *rbcpf;

  self = TypedData_Make_Struct(klass, ruby_curl_postfield, &ruby_curl_postfield_data_type, rbcpf);
  MEMZERO(rbcpf, ruby_curl_postfield, 1);
 
  // wierdness - we actually require two args, unless a block is provided, but
  // we have to work that out below.
  rb_scan_args(argc, argv, "12&", &rbcpf->name, &rbcpf->content, &rbcpf->content_type, &rbcpf->content_proc);

  // special handling if theres a block, second arg is actually content_type
  if (rbcpf->content_proc != Qnil) {
    if (rbcpf->content != Qnil) {
      // we were given a content-type
      rbcpf->content_type = rbcpf->content;
      rbcpf->content = Qnil;
    } else {
      // default content type      
      rbcpf->content_type = Qnil;
    }
  } else {
    // no block, so make sure content was provided    
    if (rbcpf->content == Qnil) {
      rb_raise(rb_eArgError, "Incorrect number of arguments (expected 2 or 3)");
    }    
  }
      
  /* assoc objects */
  rbcpf->local_file = Qnil;
  rbcpf->remote_file = Qnil;
  rbcpf->buffer_str = Qnil;
 
  return self;
}

/*
 * call-seq:
 *   Curl::PostField.file(name, local_file_name) => #<Curl::PostField...>
 *   Curl::PostField.file(name, local_file_name, remote_file_name = local_file_name) => #<Curl::PostField...>
 *   Curl::PostField.file(name, remote_file_name) { |field| ... } => #<Curl::PostField...>
 * 
 * Create a new Curl::PostField for a file upload field, supplying the local filename
 * to read from, and optionally the remote filename (defaults to the local name).
 * 
 * The block form allows a block to supply the content for this field, called
 * during the perform. The block should return a ruby string with the field
 * data.
 */
static VALUE ruby_curl_postfield_new_file(int argc, VALUE *argv, VALUE klass) {
  // TODO needs to handle content-type too
  VALUE self;
  ruby_curl_postfield *rbcpf;

  self = TypedData_Make_Struct(klass, ruby_curl_postfield, &ruby_curl_postfield_data_type, rbcpf);
  MEMZERO(rbcpf, ruby_curl_postfield, 1);

  rb_scan_args(argc, argv, "21&", &rbcpf->name, &rbcpf->local_file, &rbcpf->remote_file, &rbcpf->content_proc);

  // special handling if theres a block, second arg is actually remote name.
  if (rbcpf->content_proc != Qnil) {
    if (rbcpf->local_file != Qnil) {
      // we were given a local file
      if (rbcpf->remote_file == Qnil) {
        // we weren't given a remote, so local is actually remote
        // (correct block call form)
        rbcpf->remote_file = rbcpf->local_file;
      }
 
      // Shouldn't get a local file, so can ignore it.
      rbcpf->local_file = Qnil;
    }
  } else {
    if (rbcpf->remote_file == Qnil) {
      rbcpf->remote_file = rbcpf->local_file;
    }
  }
 
  /* assoc objects */
  rbcpf->content = Qnil;
  rbcpf->content_type = Qnil;
  rbcpf->buffer_str = Qnil;
 
  return self;
}

/* ================= ATTRIBUTES ====================*/

/*
 * call-seq:
 *   field.name = "name"                            => "name"
 * 
 * Set the POST field name for this PostField.
 */
static VALUE ruby_curl_postfield_name_set(VALUE self, VALUE name) {
  CURB_OBJECT_SETTER(ruby_curl_postfield, name);
}

/*
 * call-seq:
 *   field.name                                       => "name"
 * 
 * Obtain the POST field name for this PostField.
 */ 
static VALUE ruby_curl_postfield_name_get(VALUE self) {
  CURB_OBJECT_GETTER(ruby_curl_postfield, name);
}

/*
 * call-seq:
 *   field.content = "content"                        => "content"
 * 
 * Set the POST field content for this PostField. Ignored when a 
 * content_proc is supplied via either +Curl::PostField.file+ or 
 * +set_content_proc+.
 */
static VALUE ruby_curl_postfield_content_set(VALUE self, VALUE content) {
  CURB_OBJECT_SETTER(ruby_curl_postfield, content);
}

/*
 * call-seq:
 *   field.content                                    => "content"
 * 
 * Obtain the POST field content for this PostField.
 */ 
static VALUE ruby_curl_postfield_content_get(VALUE self) {
  CURB_OBJECT_GETTER(ruby_curl_postfield, content);
}

/*
 * call-seq:
 *   field.content_type = "content_type"              => "content_type"
 * 
 * Set the POST field Content-type for this PostField.
 */
static VALUE ruby_curl_postfield_content_type_set(VALUE self, VALUE content_type) {
  CURB_OBJECT_SETTER(ruby_curl_postfield, content_type);
}

/*
 * call-seq:
 *   field.content_type                               => "content_type"
 * 
 * Get the POST field Content-type for this PostField.
 */ 
static VALUE ruby_curl_postfield_content_type_get(VALUE self) {
  CURB_OBJECT_GETTER(ruby_curl_postfield, content_type);
}

/*
 * call-seq:
 *   field.local_file = "filename"                    => "filename"
 * 
 * Set the POST field local filename for this PostField (when performing
 * a file upload). Ignored when a content_proc is supplied via either 
 * +Curl::PostField.file+ or +set_content_proc+.
 */
static VALUE ruby_curl_postfield_local_file_set(VALUE self, VALUE local_file) {
  CURB_OBJECT_SETTER(ruby_curl_postfield, local_file);
}

/*
 * call-seq:
 *   field.local_file                                 => "filename"
 * 
 * Get the POST field local filename for this PostField (when performing
 * a file upload). 
 */ 
static VALUE ruby_curl_postfield_local_file_get(VALUE self) {
  CURB_OBJECT_GETTER(ruby_curl_postfield, local_file);
}

/*
 * call-seq:
 *   field.remote_file = "filename"                   => "filename"
 * 
 * Set the POST field remote filename for this PostField (when performing
 * a file upload). If no remote filename is provided, and no content_proc
 * is supplied, the local filename is used. If no remote filename is 
 * specified when a content_proc is used, an exception will be raised 
 * during the perform. 
 */
static VALUE ruby_curl_postfield_remote_file_set(VALUE self, VALUE remote_file) {
  CURB_OBJECT_SETTER(ruby_curl_postfield, remote_file);
}

/*
 * call-seq:
 *   field.local_file                                 => "filename"
 * 
 * Get the POST field remote filename for this PostField (when performing
 * a file upload).
 */ 
static VALUE ruby_curl_postfield_remote_file_get(VALUE self) {
  CURB_OBJECT_GETTER(ruby_curl_postfield, remote_file);
}

/*
 * call-seq:
 *   field.set_content_proc { |field| ... }           => <old proc>
 * 
 * Set a content proc for this field. This proc will be called during the
 * perform to supply the content for this field, overriding any setting
 * of +content+ or +local_file+.
 */
static VALUE ruby_curl_postfield_content_proc_set(int argc, VALUE *argv, VALUE self) {
  CURB_HANDLER_PROC_SETTER(ruby_curl_postfield, content_proc);
}

/*
 * call-seq:
 *   field.to_str                                     => "name=value"
 *   field.to_s                                       => "name=value"
 * 
 * Obtain a String representation of this PostField in url-encoded 
 * format. This is used to construct the post data for non-multipart
 * POSTs.
 * 
 * Only content fields may be converted to strings.
 */
static VALUE ruby_curl_postfield_to_str(VALUE self) {
  ruby_curl_postfield *rbcpf;
  VALUE result = Qnil;
  VALUE name = Qnil;
  char *tmpchrs;
#ifdef HAVE_CURL_EASY_ESCAPE
  CURL *curl_handle = NULL;
#endif

  TypedData_Get_Struct(self, ruby_curl_postfield, &ruby_curl_postfield_data_type, rbcpf);

  if (rbcpf->name != Qnil) {
    name = rbcpf->name;
    if (TYPE(name) != T_STRING) {
      if (rb_respond_to(name, rb_intern("to_s")))
        /* rb_obj_as_string always yields a String, even if #to_s misbehaves
         * and returns a non-String; a raw rb_funcall result could later be
         * handed to RSTRING_PTR/RSTRING_LEN and crash. */
        name = rb_obj_as_string(name);
      else
        name = Qnil;
    }
  }
  if (name == Qnil) {
    rb_raise(eCurlErrInvalidPostField,
             "Cannot convert unnamed field to string %s:%d, make sure your field name responds_to :to_s",
             __FILE__, __LINE__);
  }
  /* Force field name to UTF-8 before escaping */
  VALUE name_utf8 = rb_str_export_to_enc(name, rb_utf8_encoding());

  /* Resolve and coerce the content before creating the curl handle: the
   * content proc, #to_s and the UTF-8 export can all raise, which would
   * otherwise leak the handle. */
  VALUE tmpcontent = Qnil;
  if (rbcpf->content_proc != Qnil) {
    tmpcontent = rb_funcall(rbcpf->content_proc, idCall, 1, self);
  } else if (rbcpf->content != Qnil) {
    tmpcontent = rbcpf->content;
  } else if (rbcpf->local_file != Qnil) {
    tmpcontent = rbcpf->local_file;
  } else if (rbcpf->remote_file != Qnil) {
    tmpcontent = rbcpf->remote_file;
  } else {
    tmpcontent = rb_str_new2("");
  }
  if (TYPE(tmpcontent) != T_STRING) {
    if (rb_respond_to(tmpcontent, rb_intern("to_s")))
      /* rb_obj_as_string always yields a String, even if #to_s misbehaves */
      tmpcontent = rb_obj_as_string(tmpcontent);
    else
      rb_raise(rb_eRuntimeError,
               "postfield(%"PRIsVALUE") is not a string and does not respond_to to_s",
               name);
  }
  /* Force content to UTF-8 before escaping */
  VALUE content_utf8 = rb_str_export_to_enc(tmpcontent, rb_utf8_encoding());

#ifdef HAVE_CURL_EASY_ESCAPE
  curl_handle = curl_easy_init();
  if (!curl_handle) {
    rb_raise(eCurlErrInvalidPostField, "Failed to initialize curl handle for escaping");
  }
  tmpchrs = curl_easy_escape(curl_handle, StringValuePtr(name_utf8), (int)RSTRING_LEN(name_utf8));
  if (!tmpchrs) {
    curl_easy_cleanup(curl_handle);
    rb_raise(eCurlErrInvalidPostField, "Failed to url-encode name");
  }
#else
  tmpchrs = curl_escape(StringValuePtr(name_utf8), (int)RSTRING_LEN(name_utf8));
  if (!tmpchrs) {
    rb_raise(eCurlErrInvalidPostField, "Failed to url-encode name");
  }
#endif

  VALUE escd_name = rb_str_new2(tmpchrs);
  curl_free(tmpchrs);

#ifdef HAVE_CURL_EASY_ESCAPE
  tmpchrs = curl_easy_escape(curl_handle, StringValuePtr(content_utf8), (int)RSTRING_LEN(content_utf8));
  if (!tmpchrs) {
    curl_easy_cleanup(curl_handle);
    rb_raise(eCurlErrInvalidPostField, "Failed to url-encode content");
  }
#else
  tmpchrs = curl_escape(StringValuePtr(content_utf8), (int)RSTRING_LEN(content_utf8));
  if (!tmpchrs) {
    rb_raise(eCurlErrInvalidPostField, "Failed to url-encode content");
  }
#endif

  VALUE escd_content = rb_str_new2(tmpchrs);
#ifdef HAVE_CURL_EASY_ESCAPE
  curl_free(tmpchrs);
  curl_easy_cleanup(curl_handle);
#else
  curl_free(tmpchrs);
#endif

  result = escd_name;
  rb_str_cat(result, "=", 1);
  rb_str_concat(result, escd_content);

  return result;
}


/* =================== INIT LIB =====================*/
void init_curb_postfield() {
  VALUE sc;

  idCall = rb_intern("call");
  
  cCurlPostField = rb_define_class_under(mCurl, "PostField", rb_cObject);

  rb_undef_alloc_func(cCurlPostField);

  /* Class methods */
  rb_define_singleton_method(cCurlPostField, "content", ruby_curl_postfield_new_content, -1);
  rb_define_singleton_method(cCurlPostField, "file", ruby_curl_postfield_new_file, -1);
  
  sc = rb_singleton_class(cCurlPostField);
  rb_undef(sc, rb_intern("new"));
  
  rb_define_method(cCurlPostField, "name=", ruby_curl_postfield_name_set, 1);
  rb_define_method(cCurlPostField, "name", ruby_curl_postfield_name_get, 0);  
  rb_define_method(cCurlPostField, "content=", ruby_curl_postfield_content_set, 1);
  rb_define_method(cCurlPostField, "content", ruby_curl_postfield_content_get, 0);  
  rb_define_method(cCurlPostField, "content_type=", ruby_curl_postfield_content_type_set, 1);
  rb_define_method(cCurlPostField, "content_type", ruby_curl_postfield_content_type_get, 0);  
  rb_define_method(cCurlPostField, "local_file=", ruby_curl_postfield_local_file_set, 1);
  rb_define_method(cCurlPostField, "local_file", ruby_curl_postfield_local_file_get, 0);  
  rb_define_method(cCurlPostField, "remote_file=", ruby_curl_postfield_remote_file_set, 1);
  rb_define_method(cCurlPostField, "remote_file", ruby_curl_postfield_remote_file_get, 0);  
  
  rb_define_method(cCurlPostField, "set_content_proc", ruby_curl_postfield_content_proc_set, -1);  

  rb_define_method(cCurlPostField, "to_str", ruby_curl_postfield_to_str, 0);  
  rb_define_alias(cCurlPostField, "to_s", "to_str");
}
