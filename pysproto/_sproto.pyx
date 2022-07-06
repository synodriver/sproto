# cython: language_level=3
cimport cython
from cpython.bool cimport PyBool_FromLong
from cpython.bytes cimport (PyBytes_AsStringAndSize, PyBytes_Check,
                            PyBytes_FromStringAndSize)
from cpython.dict cimport (PyDict_Check, PyDict_GetItemString, PyDict_New,
                           PyDict_SetItem, PyDict_SetItemString)
from cpython.exc cimport PyErr_Occurred, PyErr_Print
from cpython.float cimport PyFloat_AsDouble, PyFloat_Check, PyFloat_FromDouble
from cpython.list cimport PyList_Append, PyList_Check, PyList_New, PyList_Size
from cpython.long cimport (PyLong_AsLong, PyLong_AsLongLong, PyLong_Check,
                           PyLong_FromLong, PyLong_FromLongLong)
from cpython.mem cimport PyMem_Free, PyMem_Malloc, PyMem_Realloc
from cpython.object cimport PyObject
from cpython.ref cimport Py_TYPE
from cpython.unicode cimport PyUnicode_DecodeUTF8
from libc.stdint cimport int32_t, int64_t, uint8_t
from libc.string cimport memcpy

from pysproto cimport sproto


cdef extern from "Python.h":
    char* PyUnicode_AsUTF8AndSize(object data, Py_ssize_t* l)


class SprotoError(Exception):
    pass

cdef struct encode_ud:
    PyObject *data  # dict
    PyObject *values

# cdef struct decode_ud:
#     PyObject* data # type: dict
#     PyObject* key
#     int deep
#     int mainindex_tag

cdef struct decode_ud:
    int mainindex
    PyObject *data  # dict
    PyObject *map_key

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
    cdef:
        encode_ud *self = <encode_ud*>args.ud
        const char * tagname = args.tagname
        int type = args.type
        int index = args.index
        int length = args.length
        object data
        int count
        long long i, vh

        char* ptr
        Py_ssize_t l

        encode_ud sub
    cdef PyObject* tmp =  PyDict_GetItemString(<object>self.data, tagname)
    if tmp == NULL:
        if index > 0:
            return sproto.SPROTO_CB_NOARRAY
        return sproto.SPROTO_CB_NIL
    data = <object>tmp
    if index > 0:
        if not PyList_Check(data):
            if PyDict_Check(data):
                count = 0
                for key, value in data.items():
                    count +=1
                    if index == count:
                        data = value
                        break
                if index > count:
                    return sproto.SPROTO_CB_NIL
            else:
                try:
                    raise SprotoError("Expected List or Dict for tagname:%s" % tagname)
                finally:
                    return sproto.SPROTO_CB_ERROR
        else:
            if index > <int>PyList_Size(data):
                # printf("data is finish, index:%d, len:%d\n", index, len)
                return sproto.SPROTO_CB_NIL
            data = data[index - 1]

    if type == sproto.SPROTO_TINTEGER:
        if PyLong_Check(data) or (args.extra and PyFloat_Check(data)):
            if args.extra:
                i = <long long>(PyFloat_AsDouble(data) * args.extra + 0.5)
                # printf("input data:%lld\n", i)
            else:
                i = PyLong_AsLongLong(data)
            vh = i >> 31
            if vh == 0 or vh == -1:
                (<int32_t *>args.value)[0] = <int32_t>i
                return 4
            else:
                (<int64_t *>args.value)[0] = <int64_t>i
                return 8
        else:
            try:
                raise SprotoError("type mismatch, tag:%s, expected int or long, got:%s\n", tagname, Py_TYPE(data).tp_name)
            finally:
                return -1
    elif type == sproto.SPROTO_TBOOLEAN: # https://github.com/spin6lock/python-sproto/blob/py3_test/src/pysproto/python_sproto.c#L111
        if isinstance(data, bool):
            if data:
                (<int *> args.value)[0] = 1
            else:
                (<int *> args.value)[0] = 0
        return 4
    elif type == sproto.SPROTO_TSTRING: # L120
        if args.extra == sproto.SPROTO_TSTRING_BINARY:   # binary
            if not PyBytes_Check(data):
                try:
                    raise SprotoError("type mismatch, tag:%s, expected bytes, got:%s\n", tagname, Py_TYPE(data).tp_name)
                finally:
                    return sproto.SPROTO_CB_ERROR
            PyBytes_AsStringAndSize(data, &ptr, &l)
        else:
            if not isinstance(data, str):
                try:
                    raise SprotoError("type mismatch, tag:%s, expected unicode, got:%s\n", tagname, Py_TYPE(data).tp_name)
                finally:
                    return sproto.SPROTO_CB_ERROR
            ptr = <char*>PyUnicode_AsUTF8AndSize(data, &l)
        if <int>l>length:
            return sproto.SPROTO_CB_ERROR
        memcpy(args.value, ptr, <size_t> l)
        return <int>l
    elif type == sproto.SPROTO_TSTRUCT: # L152
        sub.data = <PyObject*>data
        with nogil:
            r = sproto.sproto_encode(args.subtype, args.value, length, encode, &sub)
        if r<0:
            return sproto.SPROTO_CB_ERROR
        return r
    else:
        return 0

# cdef int decode(const sproto.sproto_arg *args) except * with gil: # except * with gil
#     cdef decode_ud *ud = <decode_ud *> args.ud
#     self_d = <dict> ud.data
#     # todo: need check deep?
#     if args.index != 0:
#         if args.tagname not in self_d:
#             if args.mainindex >= 0:
#                 c = {}
#             else:
#                 c = []
#             self_d[args.tagname] = c
#         else:
#             c = self_d[args.tagname]
#         if args.index < 0:
#             return 0
#
#     ret = None
#     cdef decode_ud sub
#     if args.type == sproto.SPROTO_TINTEGER:
#         if args.extra:
#             ret = (<int64_t *> args.value)[0]
#             ret = <double> ret / args.extra
#         else:
#             ret = (<int64_t *> args.value)[0]
#     elif args.type == sproto.SPROTO_TBOOLEAN:
#         ret = True if (<int64_t *> args.value)[0] > 0 else False
#     elif args.type == sproto.SPROTO_TSTRING:
#         ret = (<char *> args.value)[:args.length]
#     elif args.type == sproto.SPROTO_TSTRUCT:
#         sub.deep = ud.deep + 1
#         sub_d = {}
#         sub.data = <PyObject *> sub_d
#         if args.mainindex >= 0:
#             sub.mainindex_tag = args.mainindex
#             r = sproto.sproto_decode(args.subtype, args.value, args.length, decode, &sub)
#             if r < 0:
#                 return sproto.SPROTO_CB_ERROR
#             if r != args.length:
#                 return r
#             if sub.key == NULL:
#                 raise SprotoError("can't find mainindex (tag_or_name=%d) in [%s]a" % (args.mainindex, args.tagname))
#             c[<object> (sub.key)] = sub_d
#             return 0
#         else:
#             sub.mainindex_tag = -1
#             r = sproto.sproto_decode(args.subtype, args.value, args.length, decode, &sub)
#             if r < 0:
#                 return sproto.SPROTO_CB_ERROR
#             if r != args.length:
#                 return r
#             ret = sub_d
#     else:
#         raise SprotoError("Decode error, got invalid type %d" % args.type)
#
#     if args.index > 0:
#         c.append(ret)
#     else:
#         if ud.mainindex_tag == args.tagid:
#             ud.key = <PyObject *> ret
#         self_d[args.tagname] = ret
#     return 0


cdef int decode(const sproto.sproto_arg *args) except * with gil: # except * with gil
    cdef:
        decode_ud *self = <decode_ud *>args.ud
        const char *tagname = args.tagname
        int tagid = args.tagid
        int type = args.type
        int index = args.index
        int mainindex = args.mainindex
        Py_ssize_t length = args.length

        PyObject * obj=self.data
        object data = None # to return

        # long long i
        int64_t tmp
        # double result
        decode_ud sub
    if index != 0:
        obj = PyDict_GetItemString(<object>self.data, tagname)
        if obj == NULL:
            if mainindex >= 0:
                d = PyDict_New()
                obj = <PyObject*>d
            else:
                l = PyList_New(0)
                obj = <PyObject*>l
            PyDict_SetItemString(<object>self.data, tagname, <object>obj)
            if index < 0:
                return 0
    if type == sproto.SPROTO_TINTEGER:
        # args.extra = 0 length = 8
        if args.extra:
            tmp = (<int64_t*>args.value)[0]
            # result = <double>tmp / args.extra
            data = PyFloat_FromDouble(<double>tmp / args.extra)
        elif length == 4:
            data = PyLong_FromLong((<int32_t*>args.value)[0])
        elif length == 8:
            data = PyLong_FromLongLong((<int64_t *> args.value)[0]) # data = 1
        else:
            try:
                raise SprotoError("unexpected integer length: %d" % length)
            finally:
                return sproto.SPROTO_CB_ERROR
    elif type == sproto.SPROTO_TBOOLEAN:
        data = PyBool_FromLong((<int *>args.value)[0])
    elif type == sproto.SPROTO_TSTRING:
        if args.extra == sproto.SPROTO_TSTRING_STRING:
            data = PyUnicode_DecodeUTF8(<char*>args.value, length, "can not decode utf8-encode unicode string")
        else:
            data = PyBytes_FromStringAndSize(<char*>args.value, length)
    elif type == sproto.SPROTO_TSTRUCT:
        d = PyDict_New()
        sub.data = <PyObject*>d
        if mainindex >= 0:
            sub.mainindex = args.mainindex
            with nogil:
                r = sproto.sproto_decode(args.subtype, args.value, <int>length, decode, &sub)
            if r<0:
                return sproto.SPROTO_CB_ERROR
            if r!=length:
                return r
            PyDict_SetItem(<object>obj, <object>sub.map_key, <object>sub.data)
        else:
            sub.mainindex = -1
            data = <object>sub.data
            with nogil:
                r = sproto.sproto_decode(args.subtype, args.value, <int>length, decode, &sub)
            if r<0:
                return sproto.SPROTO_CB_ERROR
            if r!=length:
                return r
    if data:
        if PyList_Check(<object>obj):
            PyList_Append(<object>obj , data)
        else:
            PyDict_SetItemString(<object>self.data, tagname, data)
        # Py_XDECREF(<PyObject*>data) catch you! damn refcnt!
        if self.mainindex == tagid:
            self.map_key = <PyObject*>data
    else:
        if self.mainindex == tagid:
            try:
                raise SprotoError("map key type not support")
            finally:
                return sproto.SPROTO_CB_ERROR
    return 0


@cython.freelist(8)
@cython.no_gc
@cython.final
cdef class SprotoType:
    """Wrapper around struct sproto_type"""
    cdef sproto.sproto_type_t *st

    @staticmethod
    cdef inline SprotoType from_ptr(sproto.sproto_type_t *st):
        cdef SprotoType self = SprotoType.__new__(SprotoType)
        self.st = st
        return self

    @property
    def name(self):
        return (<bytes>sproto.sproto_name(self.st)).decode()

    cpdef inline dict decode(self, const uint8_t[::1] buffer):
        assert self.st != NULL
        cdef:
            dict d = {}
            decode_ud ud
            int r
        ud.data = <PyObject*>d
        with nogil:
            r = sproto.sproto_decode(self.st, <void*>&buffer[0], <int>buffer.shape[0], decode, &ud)
        if PyErr_Occurred():
            PyErr_Print()
            raise SprotoError("decode error")
        if r < 0:
            raise SprotoError("decode error")
        return d

    cpdef inline int encode_into(self, dict data, uint8_t[::1] buffer):
        """
        encode data into buffer
        :param data: 
        :param buffer: 
        :return: buffer updated
        """
        assert self.st != NULL
        cdef:
            int ret
            encode_ud ud = encode_ud(<PyObject*>data, NULL)
        with nogil:
            ret = sproto.sproto_encode(self.st, <void*>&buffer[0], <int>buffer.shape[0], encode, &ud)
        if ret < 0:
            raise SprotoError("buffer is too small")
        return ret

    cpdef inline bytes encode(self, dict data):
        assert self.st != NULL
        cdef:
            int ret
            encode_ud ud = encode_ud(<PyObject *> data, NULL)
            size_t prealloc = 1024
        cdef uint8_t * buf = <uint8_t *>PyMem_Malloc(prealloc)
        if buf == NULL:
            raise MemoryError
        try:
            while True:
                with nogil:
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

@cython.freelist(8)
@cython.no_gc
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
            self.sp = NULL

    cpdef inline void dump(self):
        assert self.sp != NULL
        with nogil:
            sproto.sproto_dump(self.sp)

    cpdef inline SprotoType querytype(self, type_name):
        assert self.sp != NULL
        type_name = _ensure_bytes(type_name)
        cdef sproto.sproto_type_t *st
        cdef char* type_name_c = <char*>type_name
        with nogil:
            st = sproto.sproto_type(self.sp, type_name_c)
        if st:
            return SprotoType.from_ptr(st)

    cpdef inline object protocol(self, tag_or_name):
        assert self.sp != NULL
        cdef:
            const char* name
            int tag
            sproto.sproto_type_t * request
            sproto.sproto_type_t * response
            object ret1, ret2, ret3  # firtst ret params
        if isinstance(tag_or_name, int):
            tag = <int>PyLong_AsLong(tag_or_name)
            with nogil:
                name = sproto.sproto_protoname(self.sp, tag)
            if name == NULL:
                return None
            ret1  = (<bytes>name).decode()
        elif isinstance(tag_or_name, (str, bytes)):
            bt = _ensure_bytes(tag_or_name)
            name = <const char*>bt
            with nogil:
                tag = sproto.sproto_prototag(self.sp, name)
            if tag < 0:
                return None
            ret1  = PyLong_FromLong(<int>tag)
        with nogil:
            request = sproto.sproto_protoquery(self.sp, tag, sproto.SPROTO_REQUEST)
        if request == NULL:
            ret2 = None
        else:
            ret2 = SprotoType.from_ptr(request)
        with nogil:
            response = sproto.sproto_protoquery(self.sp, tag, sproto.SPROTO_RESPONSE)
        if response == NULL:
            ret3 = None
        else:
            ret3 = SprotoType.from_ptr(response)
        return (ret1, ret2, ret3)

    cpdef inline int sproto_protoresponse(self, int proto) nogil:
        return sproto.sproto_protoresponse(self.sp, proto)

cpdef inline int pack_into(const uint8_t[::1] inp, uint8_t[::1] out):
    cdef:
        size_t sz = <size_t>inp.shape[0]
        size_t maxsz = (sz + 2047) / 2048 * 2 + sz + 2
        int ret
    if <size_t>out.shape[0] < maxsz:
        raise SprotoError("output buffer is too small")
    with nogil:
        ret =  sproto.sproto_pack(<void*>&inp[0], <int>inp.shape[0], <void*>&out[0], <int>maxsz)
    if <size_t>ret > maxsz:
        raise SprotoError("packing error, return size = %d" % ret)
    return ret


cpdef inline bytes pack(const uint8_t[::1] inp):
    cdef:
        size_t sz = <size_t> inp.shape[0]
        size_t maxsz = (sz + 2047) / 2048 * 2 + sz + 2
        int ret
    cdef void* out = PyMem_Malloc(maxsz)
    if out == NULL:
        raise MemoryError
    with nogil:
        ret = sproto.sproto_pack(<void *> &inp[0], <int> inp.shape[0], out, <int>maxsz)
    if <size_t>ret > maxsz:
        raise SprotoError("packing error, return size = %d" % ret)
    bt = <bytes>((<uint8_t*>out)[:ret])
    PyMem_Free(out)
    return bt


cpdef inline int unpack_into(const uint8_t[::1] inp, uint8_t[::1] out):
    cdef int ret
    with nogil:
        ret =  sproto.sproto_unpack(<void*>&inp[0], <int>inp.shape[0], <void*>&out[0], <int>out.shape[0])
    if ret < 0:
        raise SprotoError("Invalid unpack stream")
    return ret


cpdef inline bytes unpack(const uint8_t[::1] inp):
    cdef void * out = PyMem_Malloc(<size_t>sproto.ENCODE_BUFFERSIZE)
    if out == NULL:
        raise MemoryError
    cdef int osz = sproto.ENCODE_BUFFERSIZE
    cdef int ret
    with nogil:
        ret = sproto.sproto_unpack(<void *> &inp[0], <int> inp.shape[0], out, osz)
    if ret < 0:
        raise SprotoError("Invalid unpack stream")
    if ret > osz:
        out = PyMem_Realloc(out, <size_t>ret)
        if out == NULL:
            raise MemoryError
        osz = ret
        with nogil:
            ret = sproto.sproto_unpack(<void *> &inp[0], <int> inp.shape[0], out, osz)
        if ret < 0:
            raise SprotoError("Invalid unpack stream")
    bt = <bytes>((<uint8_t*>out)[:ret])
    PyMem_Free(out)
    return bt
