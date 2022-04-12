<h1 align="center"><i>✨ Pysproto ✨ </i></h1>

<h3 align="center">Another Pythonic Sproto Python binding for <a href="https://github.com/cloudwu/sproto">sproto</a> </h3>

<h3 align="center"><i>Powered by cython, high performance, pythonic</i></h3>

[![pypi](https://img.shields.io/pypi/v/sproto.svg)](https://pypi.org/project/sproto/)
![python](https://img.shields.io/pypi/pyversions/sproto)
![implementation](https://img.shields.io/pypi/implementation/sproto)
![wheel](https://img.shields.io/pypi/wheel/sproto)
![license](https://img.shields.io/github/license/synodriver/sproto.svg)
![action](https://img.shields.io/github/workflow/status/synodriver/sproto/build%20wheel)


### Usage

- encode & decode
```python
from pysproto import parse, parse_ast, Sproto
ast = parse(""".package {
                    type 0 : integer
                    session 1 : integer
                    }""")
dump = parse_ast(ast)
proto = Sproto(dump)
tp = proto.querytype("package")
encoded = tp.encode({"type": 1, "session": 2})
print(tp.decode(encoded))
```

- Public functions
```python
from typing import Union, Tuple, Optional

class Sproto:
    def dump(self)->None: ...
    def protocol(self, tag_or_name: Union[int, str]) -> Tuple[Union[int, str], Optional["SprotoType"], Optional["SprotoType"]]: ...
    def querytype(self, type_name) -> "SprotoType": ...
    def sproto_protoresponse(self, intproto) -> int: ...

class SprotoError(Exception): ...

class SprotoType:
    @classmethod
    def __init__(self, *args, **kwargs) -> None: ...
    def decode(self, buffer: bytes) -> dict: ...
    def encode(self, data: dict) -> bytes: ...
    def encode_into(self, data: dict, buffer: bytearray) -> int: ...

def pack(data: bytes) -> bytes: ...
def pack_into(data: bytes, buffer: bytearray) -> int: ...
def unpack(data: bytes) -> bytes: ...
def unpack_into(data: bytes, buffer: bytearray) -> int: ...
```
- ```xx_into``` functions accepts buffer protocol objects, which is zerocopy.