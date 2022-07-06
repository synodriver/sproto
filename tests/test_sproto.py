import gc
from random import randint
from unittest import TestCase

from pysproto import Sproto, pack, parse, parse_ast, unpack

# import sys
#
# sys.path.append("/sproto")


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

    def test_pack_unpack(self):
        def test_pack_unpack_():
            for i in range(1000):
                length = randint(1, 1000)
                data = bytes([randint(0, 255) for _ in range(length)])
                self.assertEqual(
                    unpack(pack(data)).rstrip(b"\x00"), data.rstrip(b"\x00")
                )

        self._run_gc_test(test_pack_unpack_)

    def test_dump(self):
        ast = parse(
            """.package {
                                type 0 : integer
                                session 1 : integer
                            }""",
            "",
        )
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

    def test_dump_nested(self):
        ast = parse(
            """
        .Person {
        name 0 : string
        id 1 : integer
        email 2 : string
        real 3: double

        .PhoneNumber {
            number 99 : string
            type  1000: integer
        }
        phone 4 : *PhoneNumber
        phonemap 5 : *PhoneNumber()
    }

    .AddressBook {
        person 0: *Person(id)
        others 1: *Person
    }
        """,
            "",
        )
        dump = parse_ast(ast)
        sp = Sproto(dump)
        sp.dump()

    def test_bin(self):
        sp_data = """
        .Person {
	name 0 : binary
	id 1 : integer
	email 2 : binary

	.PhoneNumber {
		number 0 : binary
		type 1 : integer
	}

	phone 3 : *PhoneNumber
	pi    4 : integer(5)
}

.AddressBook {
	person 0 : *Person(id)
	others 1 : *Person
}
        """
        ast = parse(sp_data, "")
        dump = parse_ast(ast)
        sp = Sproto(dump)
        sp.dump()

    def test_spb(self):
        """
                AddressBook
                person (0) *Person key[1]
                others (1) *Person
        Person
                name (0) binary
                id (1) integer
                email (2) binary
                phone (3) *Person.PhoneNumber
                pi (4) decimal(100000)
        Person.PhoneNumber
                number (0) binary
                type (1) integer
        """
        with open(r"person.spb", "rb") as f:
            data = f.read()
        sp = Sproto(data)
        # sp.dump()
        tp = sp.querytype("Person")
        encoded = tp.encode(
            {
                "name": b"crystal",
                "id": 1001,
                "email": b"crystal@example.com",
                "phone": [
                    {
                        "type": 1,
                        "number": b"10086",
                    },
                    {
                        "type": 2,
                        "number": b"10010",
                    },
                ],
            }
        )
        print(encoded)
        dt = tp.decode(encoded)
        print(dt)
        pass

    def tearDown(self) -> None:
        pass


if __name__ == "__main__":
    import unittest

    unittest.main()
