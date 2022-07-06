# coding:utf-8
import argparse
import os
import struct
import sys
from io import BytesIO
from typing import Union

import pysproto.sprotoparser as sprotoparser


def ensure_bytes(data) -> bytes:
    if isinstance(data, str):
        return data.encode()
    return bytes(data)


def packbytes(s: Union[bytes, str]) -> bytes:
    s = ensure_bytes(s)
    return struct.pack("<I%ds" % len(s), len(s), s)


def packvalue(v: int) -> bytes:
    v = (v + 1) * 2
    return struct.pack("<H", v)


def packfield(f):
    strtbl = BytesIO()  # todo L289
    if f["array"]:
        if f["key"]:  # if has no "key" already set to f["key"] = None
            if f.get("map", None):
                strtbl.write(b"\7\0")
            else:
                strtbl.write(b"\6\0")
        else:
            strtbl.write(b"\5\0")
    else:
        strtbl.write(b"\4\0")
    strtbl.write(b"\0\0")
    if f["builtin"] != None:
        strtbl.write(packvalue(f["builtin"]))
        if f.get("extra", None):
            strtbl.write(packvalue(f["extra"]))
        else:
            strtbl.write(b"\1\0")
        strtbl.write(packvalue(f["tag"]))
    else:
        strtbl.write(b"\1\0")
        strtbl.write(packvalue(f["type"]))
        strtbl.write(packvalue(f["tag"]))
    if f["array"]:
        strtbl.write(packvalue(1))
        if f["key"]:
            strtbl.write(packvalue(f["key"]))
            if f.get("map", None):
                strtbl.write(packvalue(f["map"]))
    strtbl.write(packbytes(f["name"]))
    return packbytes(strtbl.getvalue())


def packtype(name, t, alltypes):
    fields = []
    tmp = {}
    for f in t:  # type: dict
        tmp["array"] = f["array"]
        tmp["name"] = f["name"]
        tmp["tag"] = f["tag"]
        tmp["extra"] = f.get("decimal", None)

        tname = f["typename"]
        tmp["builtin"] = sprotoparser.builtin_types.get(tname, None)
        subtype = None

        if tname == "binary":
            tmp["extra"] = 1
        if tmp["builtin"] == None:
            assert alltypes[tname], "type %s not exists" % tname
            subtype = alltypes[tname]
            tmp["type"] = subtype["id"]
        else:
            tmp["type"] = None
        if f.get("key", None) is not None:  # todo Line 352
            assert f["array"]
            if f["key"] == "":
                tmp["map"] = 1
                c = 0
                min_t = sys.maxsize
                for n, t in enumerate(subtype["fields"]):
                    c += 1
                    if t["tag"] < min_t:
                        min_t = t["tag"]
                        f["key"] = n
                assert c == 2, (
                    "Invalid map definition: %s, must only have two fields"
                    % tmp["name"]
                )
            stfield = subtype["fields"].get(f.get("key", None), None)
            if not stfield or not stfield.get("buildin", None):
                raise AssertionError("Invalid map index :" + f["key"])
            tmp["key"] = stfield.get("tag", None)

            # tmp["key"] = subtype["fields"][f["key"]["name"]]
            # assert tmp["key"], "Invalid map index %d" % f["key"]["name"]
        else:
            tmp["key"] = None
        fields.append(packfield(tmp))
    data = BytesIO()
    if not fields:
        data.write(b"\1\0\0\0")
        data.write(packbytes(name))
        # data = [b"\1\0", b"\0\0", packbytes(name)]
    else:
        data.write(b"\2\0\0\0\0\0")
        data.write(packbytes(name))
        data.write(packbytes(b"".join(fields)))
        # data = [b"\2\0", b"\0\0", b"\0\0", packbytes(name), packbytes(b"".join(fields))]
    return packbytes(data.getvalue())


def packproto(name, p, alltypes) -> bytes:
    if "request" in p:
        request = alltypes[p["request"]]
        assert request != None, "Protocol %s request types not found" % (
            name,
            p["request"],
        )
        request = request["id"]

    tmp = BytesIO()
    tmp.write(b"\4\0\0\0")
    tmp.write(packvalue(p["tag"]))

    # tmp = ["\4\0", "\0\0", packvalue(p["tag"])]
    if "request" not in p and "response" not in p:
        tmp.getbuffer()[:2] = b"\2\0"
        # tmp[0] = "\2\0"
    else:
        if "request" in p:
            tmp.write(packvalue(alltypes[p["request"]]["id"]))
        else:
            tmp.write(b"\1\0")
        if "response" in p:
            tmp.write(packvalue(alltypes[p["response"]]["id"]))
        else:
            tmp.getbuffer()[:2] = b"\3\0"
    tmp.write(packbytes(name))
    return packbytes(tmp.getvalue())


def packgroup(t, p) -> bytes:
    """

    :param t: Type
    :param p: Protocol
    :return:
    """
    if not t:
        assert p
        return b"\0\0"
    tp = None
    alltypes = {}
    alltype_names = []
    for name in t:
        alltype_names.append(name)
    alltype_names.sort()
    for idx, name in enumerate(alltype_names):
        fields = {}
        for type_fields in t[name]:
            if (
                type_fields["typename"] in sprotoparser.builtin_types
            ):  # todo add key too nested
                fields[type_fields["name"]] = type_fields["tag"]
        alltypes[name] = {"id": idx, "fields": fields}

    tt = BytesIO()
    for name in alltype_names:
        tt.write(
            packtype(name, t[name], alltypes)
        )  # alltypes["Person"]["fields"]["key"]

    tt = packbytes(tt.getvalue())
    if p:
        tmp = []
        for name, tbl in p.iteritems():
            tmp.append(tbl)
            tbl["name"] = name
        tmp = sorted(tmp, key=lambda k: k["tag"])
        tp = BytesIO()
        for tbl in tmp:
            tp.write(packproto(tbl["name"], tbl, alltypes))
        tp = packbytes(tp.getvalue())
    result = BytesIO()
    if tp == None:
        result.write(b"\1\0\0\0")
        result.write(tt)
        # result = [b"\1\0", b"\0\0", tt]
    else:
        result.write(b"\2\0\0\0\0\0")
        result.write(tt)
        result.write(tp)
        # result = [b"\2\0", b"\0\0", b"\0\0", tt, tp]
    return result.getvalue()


def encodeall(r) -> bytes:  # todo 彻底核对lua的对应这个名字的函数
    return packgroup(r["type"], r["protocol"])


def parse_ast(ast) -> bytes:
    return encodeall(ast)


def dump(build, outfile):
    data = parse_ast(build)
    if isinstance(outfile, str):
        f = open(outfile, "wb")
        f.write(data)
        f.close()
    else:
        outfile.write(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--directory", dest="src_dir", help="sproto source files")
    parser.add_argument("-f", "--file", dest="src_file", help="sproto single file")
    parser.add_argument(
        "-o",
        "--out",
        dest="outfile",
        default="sproto.spb",
        help="specific dump binary file",
    )
    parser.add_argument(
        "-v", "--verbose", dest="verbose", action="store_true", help="show more info"
    )
    args = parser.parse_args()

    build = None
    if args.src_file:
        text = open(args.src_file, encoding="utf-8").read()
        build = sprotoparser.parse(text, os.path.basename(args.src_file))
    else:
        sproto_list = []
        for f in os.listdir(args.src_dir):
            file_path = os.path.join(args.src_dir, f)
            if os.path.isfile(file_path) and f.endswith(".sproto"):
                text = open(file_path, encoding="utf-8").read()
                sproto_list.append((text, f))

        build = sprotoparser.parse_list(sproto_list)

    if args.verbose == True:
        import json

        print(json.dumps(build, indent=4))
    dump(build, args.outfile)
