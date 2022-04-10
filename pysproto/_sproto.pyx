# cython: language_level=3
cimport cython
from libc.stdint cimport uint8_t, int64_t, int32_t
from libc.string cimport memcpy

from cpython.object cimport PyObject
from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from cpython.long cimport PyLong_AsLong, PyLong_FromLong
from cpython.exc cimport PyErr_Occurred, PyErr_Print

from pysproto cimport sproto

class SprotoError(Exception):
    pass

cdef struct encode_ud:
    PyObject *data
    int deep

cdef struct decode_ud:
    PyObject* data # type: dict
    PyObject* key
    int deep
    int mainindex_tag

cdef bytes _ensure_bytes(s):
    if s is None:
        return s
    elif isinstance(s, unicode):
        return (<unicode>s).encode()
    elif isinstance(s, bytearray):
        s = bytes(s)
    elif not isinstance(s, bytes):
        raise ValueError("expected string, got %s" % type(s))
    return <bytes>s

cdef int encode(const sproto.sproto_arg *args) except * with gil:
    cdef encode_ud *self = <encode_ud*>args.ud
    # todo check deep
    data = <object>self.data
    obj = None
    tn = args.tagname
    if args.index > 0:
        try:
            c = data[tn]
        except KeyError:
            return sproto.SPROTO_CB_NOARRAY
        if args.mainindex >= 0:
            # c is a dict
            assert isinstance(c, dict)
            c = c.values()
            c.sort()
        try:
            obj = c[args.index-1]
        except IndexError:
            return sproto.SPROTO_CB_NIL
    else:
        obj = data.get(tn)
        if obj == None:
            return sproto.SPROTO_CB_NIL
    cdef int64_t v, vh
    cdef double vn
    cdef char* ptr
    cdef encode_ud sub
    if args.type == sproto.SPROTO_TINTEGER:
        if args.extra:
            vn = obj
            v = int(vn*args.extra+0.5)
        else:
            v = obj
        vh = v >> 31
        if vh == 0 or vh == -1:
            (<int32_t *>args.value)[0] = <int32_t>v;
            return 4
        else:
            (<int64_t *>args.value)[0] = <int64_t>v;
            return 8
    elif args.type == sproto.SPROTO_TBOOLEAN:
        v = obj
        (<int *>args.value)[0] = <int>v
        return 4
    elif args.type == sproto.SPROTO_TSTRING:
        ptr = obj
        v = len(obj)
        if v > args.length:
            return sproto.SPROTO_CB_ERROR
        memcpy(args.value, ptr, <size_t>v)
        return v
    elif args.type == sproto.SPROTO_TSTRUCT:
        sub.data = <PyObject *>obj
        sub.deep = self.deep + 1
        r = sproto.sproto_encode(args.subtype, args.value, args.length, encode, &sub)
        if r < 0:
            return sproto.SPROTO_CB_ERROR
        return r
    raise SprotoError("Invalid field type %d" % args.type)

cdef int decode(const sproto.sproto_arg *args) except * with gil: # except * with gil
    cdef decode_ud *ud = <decode_ud *> args.ud
    self_d = <dict> ud.data
    # todo: need check deep?
    if args.index != 0:
        if args.tagname not in self_d:
            if args.mainindex >= 0:
                c = {}
            else:
                c = []
            self_d[args.tagname] = c
        else:
            c = self_d[args.tagname]
        if args.index < 0:
            return 0

    ret = None
    cdef decode_ud sub
    if args.type == sproto.SPROTO_TINTEGER:
        if args.extra:
            ret = (<int64_t *> args.value)[0]
            ret = <double> ret / args.extra
        else:
            ret = (<int64_t *> args.value)[0]
    elif args.type == sproto.SPROTO_TBOOLEAN:
        ret = True if (<int64_t *> args.value)[0] > 0 else False
    elif args.type == sproto.SPROTO_TSTRING:
        ret = (<char *> args.value)[:args.length]
    elif args.type == sproto.SPROTO_TSTRUCT:
        sub.deep = ud.deep + 1
        sub_d = {}
        sub.data = <PyObject *> sub_d
        if args.mainindex >= 0:
            sub.mainindex_tag = args.mainindex
            r = sproto.sproto_decode(args.subtype, args.value, args.length, decode, &sub)
            if r < 0:
                return sproto.SPROTO_CB_ERROR
            if r != args.length:
                return r
            if sub.key == NULL:
                raise SprotoError("can't find mainindex (tag_or_name=%d) in [%s]a" % (args.mainindex, args.tagname))
            c[<object> (sub.key)] = sub_d
            return 0
        else:
            sub.mainindex_tag = -1
            r = sproto.sproto_decode(args.subtype, args.value, args.length, decode, &sub)
            if r < 0:
                return sproto.SPROTO_CB_ERROR
            if r != args.length:
                return r
            ret = sub_d
    else:
        raise SprotoError("Decode error, got invalid type %d" % args.type)

    if args.index > 0:
        c.append(ret)
    else:
        if ud.mainindex_tag == args.tagid:
            ud.key = <PyObject *> ret
        self_d[args.tagname] = ret
    return 0

@cython.final
cdef class SprotoType:
    """Wrapper around struct sproto_type"""
    cdef sproto.sproto_type_t *st

    @staticmethod
    cdef inline SprotoType from_ptr(sproto.sproto_type_t *st):
        cdef SprotoType self = SprotoType.__new__()
        self.st = st
        return self

    cpdef inline tuple decode(self, const uint8_t[::1] buffer):
        assert self.st != NULL
        cdef:
            dict d = {}
            decode_ud ud = decode_ud(<PyObject*>d,NULL,0,-1)
        cdef int r = sproto.sproto_decode(self.st, <void*>&buffer[0], <int>buffer.shape[0], decode, &ud)
        if PyErr_Occurred():
            PyErr_Print()
            raise SprotoError("decode error")
        if r < 0:
            raise SprotoError("decode error")
        return d, r

    cpdef inline encode_into(self, dict data, uint8_t[::1] buffer):
        """
    
        :param data: 
        :param buffer: 
        :return: buffer updated
        """
        assert self.st != NULL
        cdef:
            int ret
            encode_ud ud = encode_ud(<PyObject*>data, 0)
        ret = sproto.sproto_encode(self.st, <void*>&buffer[0], <int>buffer.shape[0], encode, &ud)
        if ret < 0:
            raise SprotoError("buffer is too small")
        return ret

    cpdef inline bytes encode(self, dict data):
        assert self.st != NULL
        cdef:
            int ret
            encode_ud ud = encode_ud(<PyObject *> data, 0)
            size_t prealloc = 1024
        cdef uint8_t * buf = <uint8_t *>PyMem_Malloc(prealloc)
        if buf == NULL:
            raise MemoryError
        try:
            while True:
                ret = sproto.sproto_encode(self.st, buf, <int>prealloc, encode, &ud)
                if PyErr_Occurred():
                    PyErr_Print()
                    raise SprotoError("encode error")
                if ret < 0:
                    prealloc = prealloc * 2
                    buf = <uint8_t *> PyMem_Realloc(buf, prealloc)
                    if buf == NULL:
                        raise MemoryError
                else:
                    return <bytes>buf[:ret]
        finally:
            PyMem_Free(buf)


@cython.final
cdef class Sproto:
    """Wrapper around struct sproto"""
    cdef sproto.sproto * sp

    def __cinit__(self, const uint8_t[::1] buffer):
        self.sp = sproto.sproto_create(<void*>&buffer[0], buffer.shape[0])
        if self.sp is NULL:
            raise MemoryError

    def __dealloc__(self):
        if self.sp != NULL:
            sproto.sproto_release(self.sp)

    cpdef inline void dump(self):
        assert self.sp != NULL
        sproto.sproto_dump(self.sp)

    cpdef inline SprotoType querytype(self, type_name):
        assert self.sp != NULL
        type_name = _ensure_bytes(type_name)
        cdef sproto.sproto_type_t *st
        st = sproto.sproto_type(self.sp, <char*>type_name)
        if st:
            return SprotoType.from_ptr(st)

    cpdef inline tuple protocol(self, tag_or_name):
        assert self.sp != NULL
        cdef:
            const char* name
            int tag
            sproto.sproto_type_t * request
            sproto.sproto_type_t * response
            object ret1, ret2, ret3  # firtst ret params
        if isinstance(tag_or_name, int):
            tag = <int>PyLong_AsLong(tag_or_name)
            name = sproto.sproto_protoname(self.sp, tag_or_name)
            if name == NULL:
                return None
            ret1  = (<bytes>name).decode()
        elif isinstance(tag_or_name, (str, bytes)):
            bt = _ensure_bytes(tag_or_name)
            name = <const char*>bt
            tag = sproto.sproto_prototag(self.sp, name)
            if tag < 0:
                return None
            ret1  = PyLong_FromLong(<int>tag)
        request = sproto.sproto_protoquery(self.sp, tag, sproto.SPROTO_REQUEST)
        if request == NULL:
            ret2 = None
        else:
            ret2 = SprotoType.from_ptr(request)
        response = sproto.sproto_protoquery(self.sp, tag, sproto.SPROTO_RESPONSE)
        if response == NULL:
            ret3 = None
        else:
            ret3 = SprotoType.from_ptr(response)
        return ret1, ret2, ret3


cpdef inline int pack_into(const uint8_t[::1] inp, uint8_t[::1] out):
    cdef:
        size_t sz = <size_t>inp.shape[0]
        size_t maxsz = (sz + 2047) / 2048 * 2 + sz + 2
    if <size_t>out.shape[0] < maxsz:
        raise SprotoError("output buffer is too small")
    cdef int ret =  sproto.sproto_pack(<void*>&inp[0], <int>inp.shape[0], <void*>&out[0], maxsz)
    if <size_t>ret > maxsz:
        raise SprotoError("packing error, return size = %d" % ret)
    return ret


cpdef inline bytes pack(const uint8_t[::1] inp):
    cdef:
        size_t sz = <size_t> inp.shape[0]
        size_t maxsz = (sz + 2047) / 2048 * 2 + sz + 2
    cdef void* out = PyMem_Malloc(maxsz)
    if out == NULL:
        raise MemoryError
    cdef int ret = sproto.sproto_pack(<void *> &inp[0], <int> inp.shape[0], out, maxsz)
    if <size_t>ret > maxsz:
        raise SprotoError("packing error, return size = %d" % ret)
    bt = <bytes>((<uint8_t*>out)[:ret])
    PyMem_Free(out)
    return bt


cpdef inline int unpack_into(const uint8_t[::1] inp, uint8_t[::1] out):
    cdef int ret =  sproto.sproto_unpack(<void*>&inp[0], <int>inp.shape[0], <void*>&out[0], <int>out.shape[0])
    if ret < 0:
        raise SprotoError("Invalid unpack stream")
    return ret


cpdef inline bytes unpack(const uint8_t[::1] inp):
    cdef void * out = PyMem_Malloc(<size_t>sproto.ENCODE_BUFFERSIZE)
    if out == NULL:
        raise MemoryError
    cdef int osz = sproto.ENCODE_BUFFERSIZE
    cdef int ret = sproto.sproto_unpack(<void *> &inp[0], <int> inp.shape[0], out, osz)
    if ret < 0:
        raise SprotoError("Invalid unpack stream")
    if ret > osz:
        out = PyMem_Realloc(out, <size_t>ret)
        if out == NULL:
            raise MemoryError
        osz = ret
        ret = sproto.sproto_unpack(<void *> &inp[0], <int> inp.shape[0], out, osz)
        if ret < 0:
            raise SprotoError("Invalid unpack stream")
    bt = <bytes>((<uint8_t*>out)[:ret])
    PyMem_Free(out)
    return bt
