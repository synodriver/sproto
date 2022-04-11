from unittest import TestCase
from random import randint
import gc
# import sys
#
# sys.path.append("/sproto")

from pysproto import pack, unpack, parse, parse_ast, Sproto


class TestSproto(TestCase):
    def setUp(self) -> None:
        pass

    def _run_gc_test(self, run_test, times=1000):
        gc.collect()
        old_count = len(gc.get_objects())
        i = None
        for i in range(times):
            run_test()
        del i
        gc.collect()
        new_count = len(gc.get_objects())
        self.assertEqual(old_count, new_count)

    # def test_pack_unpack(self):
    #     def test_pack_unpack_():
    #         for i in range(1000):
    #             length = randint(1, 1000)
    #             data = bytes([randint(0, 255) for _ in range(length)])
    #             self.assertEqual(unpack(pack(data)).rstrip(b"\x00"), data.rstrip(b"\x00"))
    #
    #     self._run_gc_test(test_pack_unpack_)

    def test_dump(self):
        ast = parse(""".package {
                                type 0 : integer
                                session 1 : integer
                            }""", "")
        dump = parse_ast(ast)
        def test_dump_():
            sp = Sproto(dump)
            print(dump)
            sp.dump()
            tp = sp.querytype("package")
            encoded = tp.encode({"type": 1, "session": 2})  # todo wrong!
            print(encoded)
            data = tp.decode(encoded)
            self.assertEqual(data, {"type": 1, "session": 2})
        # self._run_gc_test(test_dump_, 1)
        test_dump_()
    # def test_dump_nested(self):
    #     ast = parse("""
    #     .Person {
    #     name 0 : string
    #     id 1 : integer
    #     email 2 : string
    #     real 3: double
    #
    #     .PhoneNumber {
    #         number 99 : string
    #         type  1000: integer
    #     }
    #     phone 4 : *PhoneNumber
    #     phonemap 5 : *PhoneNumber()
    # }
    #
    # .AddressBook {
    #     person 0: *Person(id)
    #     others 1: *Person
    # }
    #     """, "")
    #     dump = parse_ast(ast)
    #     sp = Sproto(dump)
    #     sp.dump()

    def tearDown(self) -> None:
        pass


if __name__ == "__main__":
    import unittest

    unittest.main()
