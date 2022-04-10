# cython: language_level=3
cdef extern from "sproto.h" nogil:
    struct sproto
    struct sproto_type_t "sproto_type"
    int SPROTO_REQUEST
    int SPROTO_RESPONSE

    # type(sproto_arg.type)
    int SPROTO_TINTEGER
    int SPROTO_TBOOLEAN
    int SPROTO_TSTRING
    int SPROTO_TDOUBLE
    int SPROTO_TSTRUCT

    # container type
    int SPROTO_TARRAY

    # sub type of string (sproto_arg.extra)
    int SPROTO_TSTRING_STRING
    int SPROTO_TSTRING_BINARY
    int SPROTO_CB_ERROR
    int SPROTO_CB_NIL
    int SPROTO_CB_NOARRAY

    sproto * sproto_create(const void * proto, size_t sz)
    void sproto_release(sproto *)

    int sproto_prototag(const sproto *, const char * name)
    const char * sproto_protoname(const sproto *, int proto)
    # SPROTO_REQUEST(0) : request, SPROTO_RESPONSE(1): response
    sproto_type_t * sproto_protoquery(const sproto *, int proto, int what)
    int sproto_protoresponse(const sproto *, int proto)

    sproto_type_t * sproto_type(const sproto *, const char * type_name)

    int sproto_pack(const void * src, int srcsz, void * buffer, int bufsz)
    int sproto_unpack(const void * src, int srcsz, void * buffer, int bufsz)

    struct sproto_arg:
        # pass
        void *ud
        const char *tagname
        int tagid
        int type
        sproto_type_t *subtype
        void *value
        int length
        int index	# array base 1, negative value indicates that it is a empty array
        int mainindex	# for map
        int extra # SPROTO_TINTEGER: decimal  SPROTO_TSTRING 0:utf8 string 1:binary

        # When interpretd two fields struct as map, the following fields must not be NULL.
        const char *ktagname
        const char *vtagname

    ctypedef int (*sproto_callback)(const sproto_arg *args) except * with gil

    int sproto_decode(const sproto_type_t * t, const void * data, int size, sproto_callback cb, void *ud)
    int sproto_encode(const sproto_type_t * t, void * buffer, int size, sproto_callback cb, void *ud)

    # for debug use
    void sproto_dump(sproto *)
    const char * sproto_name(sproto_type_t *)

cdef extern from * nogil:
    """
#define ENCODE_BUFFERSIZE 2050
    """
    int ENCODE_BUFFERSIZE