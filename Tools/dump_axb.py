#!/usr/bin/env python3

import struct
import sys

class Reader:
    def __init__(self, data, base_offset=0):
        self.data = data
        self.offset = 0
        self.base_offset = base_offset

    @property
    def absolute_offset(self):
        return self.base_offset + self.offset

    def remaining(self):
        return len(self.data) - self.offset

    def has_more(self):
        return self.offset < len(self.data)

    def require(self, count):
        if self.offset + count > len(self.data):
            raise ValueError(
                f"Unexpected end of data at offset "
                f"0x{self.absolute_offset:X}: "
                f"need {count} bytes, "
                f"only {self.remaining()} remain"
            )

    def read_bytes(self, count):
        self.require(count)

        result = self.data[
            self.offset:self.offset + count
        ]

        self.offset += count
        return result

    def peek_u8(self):
        if not self.has_more():
            return None

        return self.data[self.offset]

    def read_u8(self):
        self.require(1)

        value = self.data[self.offset]
        self.offset += 1

        return value

    def read_i8(self):
        self.require(1)

        value = struct.unpack_from(
            "<b",
            self.data,
            self.offset
        )[0]

        self.offset += 1

        return value

    def read_u16(self):
        self.require(2)

        value = struct.unpack_from(
            "<H",
            self.data,
            self.offset
        )[0]

        self.offset += 2

        return value

    def read_i16(self):
        self.require(2)

        value = struct.unpack_from(
            "<h",
            self.data,
            self.offset
        )[0]

        self.offset += 2

        return value

    def read_u32(self):
        self.require(4)

        value = struct.unpack_from(
            "<I",
            self.data,
            self.offset
        )[0]

        self.offset += 4

        return value

    def read_i32(self):
        self.require(4)

        value = struct.unpack_from(
            "<i",
            self.data,
            self.offset
        )[0]

        self.offset += 4

        return value

    def read_f32(self):
        self.require(4)

        value = struct.unpack_from(
            "<f",
            self.data,
            self.offset
        )[0]

        self.offset += 4

        return value

    def read_f64(self):
        self.require(8)

        value = struct.unpack_from(
            "<d",
            self.data,
            self.offset
        )[0]

        self.offset += 8

        return value

    def read_string(self, length_bytes=1):
        if length_bytes == 1:
            length = self.read_u8()

        elif length_bytes == 2:
            length = self.read_u16()

        else:
            raise ValueError(
                f"Invalid string length size: {length_bytes}"
            )

        raw = self.read_bytes(length)

        try:
            return raw.decode("utf-8")

        except UnicodeDecodeError as e:
            string_offset = (
                self.absolute_offset - length
            )

            raise ValueError(
                f"Invalid UTF-8 string at offset "
                f"0x{string_offset:X}: "
                f"{raw.hex(' ')}"
            ) from e

def type_name(tag):
    names = {
        0x00: "unknown",
        0x01: "bool",
        0x02: "byte",
        0x03: "ubyte",
        0x04: "short",
        0x05: "ushort",
        0x06: "int",
        0x07: "uint",
        0x08: "float",
        0x09: "double",
        0x10: "vector",
        0x20: "color4",
        0x30: "array",
        0x50: "string",
    }

    return names.get(
        tag,
        f"<tag {tag}>"
    )

def format_float(value):
    """
    Keep the output readable while avoiding
    things like -0.0.
    """

    if abs(value) < 0.0000005:
        value = 0.0

    return str(round(value, 6))

def decode_vector(reader):
    """
    Vector format:

        u8 component_count
        float component
        float component
        ...

    Example:

        02
        9A 99 99 3F
        00 00 80 3F

    = [1.2, 1.0]
    """

    component_count = reader.read_u8()

    values = []

    for _ in range(component_count):
        value = reader.read_f32()
        values.append(format_float(value))

    return "[" + ", ".join(values) + "]"

def decode_expression_value(reader, tag):
    #bool
    if tag == 0x01:
        return (
            "true"
            if reader.read_u8() != 0
            else "false"
        )

    # signed byte
    elif tag == 0x02:
        return str(reader.read_i8())

    # unsigned byte
    elif tag == 0x03:
        return str(reader.read_u8())

    # signed short
    elif tag == 0x04:
        return str(reader.read_i16())

    # ushort
    elif tag == 0x05:
        return str(reader.read_u16())

    # int
    elif tag == 0x06:
        return str(reader.read_i32())

    # uint
    elif tag == 0x07:
        return str(reader.read_u32())

    # float
    elif tag == 0x08:
        return format_float(
            reader.read_f32()
        )

    # double
    elif tag == 0x09:
        return format_float(
            reader.read_f64()
        )

    # vector
    elif tag == 0x10:
        return decode_vector(reader)

    # color4
    elif tag == 0x20:
        value = reader.read_u32()

        return f"color4(#{value:08X})"

    # string
    elif tag == 0x50:
        value = reader.read_string(2)

        return '"' + value + '"'

    # unknown
    else:
        return (
            f"<unknown value for tag "
            f"0x{tag:02X}>"
        )


def decode_array_value(reader, element_tag):
    """
    Array default value format:

        u8 element_count

        element 0
        element 1
        element 2
        ...

    For example, vertices:

        03

        02 <float> <float>
        02 <float> <float>
        02 <float> <float>
    """

    count = reader.read_u8()

    values = []

    for _ in range(count):
        value = decode_expression_value(
            reader,
            element_tag
        )

        values.append(value)

    return values

def parse_metadata(data, offset, size):

    print("--- METADATA SECTION ---")

    if size == 0:
        print("(empty)")
        return

    section = data[
        offset:offset + size
    ]

    reader = Reader(
        section,
        base_offset=offset
    )

    polygon_index = 0

    print(
        f"Polygon {polygon_index}:"
    )

    while reader.has_more():

        start = reader.absolute_offset

        try:

            # 0xFF separates metadata blocks
            if reader.peek_u8() == 0xFF:

                reader.read_u8()

                polygon_index += 1

                print()
                print(
                    f"Polygon {polygon_index}:"
                )

                continue

            key = reader.read_string(1)

            tag = reader.read_u8()

            value = decode_expression_value(
                reader,
                tag
            )

            print(
                f"  @{key} = {value}"
            )

        except Exception as e:

            print(
                f"  ERROR at 0x{start:X}: {e}"
            )

            break


# ============================================================
# Polygon section
# ============================================================

def parse_polygon_section(
    data,
    offset,
    size,
    polygon_count
):

    print()
    print("--- POLYGON SECTION ---")
    print()

    section = data[
        offset:offset + size
    ]

    reader = Reader(
        section,
        base_offset=offset
    )

    for polygon_index in range(polygon_count):

        polygon_start = reader.absolute_offset

        # ----------------------------------------------------
        # Polygon name
        # ----------------------------------------------------

        name = reader.read_string(1)

        # ----------------------------------------------------
        # Template
        # ----------------------------------------------------

        template_length = reader.read_u8()

        template = None

        if template_length > 0:

            raw_template = reader.read_bytes(
                template_length
            )

            try:

                template = raw_template.decode(
                    "utf-8"
                )

            except UnicodeDecodeError as e:

                raise ValueError(
                    f"Invalid UTF-8 template at "
                    f"0x{reader.absolute_offset - template_length:X}: "
                    f"{raw_template.hex(' ')}"
                ) from e

        # ----------------------------------------------------
        # Polygon header
        # ----------------------------------------------------

        if template:

            print(
                f"Polygon {name} : "
                f"{template} {{"
            )

        else:

            print(
                f"Polygon {name} {{"
            )

        # ----------------------------------------------------
        # Number of fields
        # ----------------------------------------------------

        fields_count = reader.read_u16()

        # ----------------------------------------------------
        # Fields
        # ----------------------------------------------------

        for field_index in range(fields_count):

            field_offset = reader.absolute_offset

            field_name = reader.read_string(1)

            tag = reader.read_u8()

            # =================================================
            # ARRAY FIELD
            # =================================================

            if tag == 0x30:

                # ---------------------------------------------
                # Element type
                # ---------------------------------------------

                element_tag = reader.read_u8()

                # ---------------------------------------------
                # Array parameter
                # ---------------------------------------------
                #
                # In your 4.3 file this is:
                #
                #   00 00
                #
                # It is NOT the number of elements.
                #
                # Keep it as metadata until we know its
                # exact semantic meaning.
                # ---------------------------------------------

                array_parameter = reader.read_u16()

                # ---------------------------------------------
                # Has default
                # ---------------------------------------------

                has_default = reader.read_u8()

                element_type = type_name(
                    element_tag
                )

                # ---------------------------------------------
                # No default
                # ---------------------------------------------

                if not has_default:

                    print(
                        f"  array<{element_type}> "
                        f"{field_name}"
                        f"[{array_parameter}];"
                    )

                    continue

                # ---------------------------------------------
                # Decode array default value
                # ---------------------------------------------

                values = decode_array_value(
                    reader,
                    element_tag
                )

                print(
                    f"  array<{element_type}> "
                    f"{field_name}"
                    f"[{array_parameter}] = "
                    f"[{', '.join(values)}];"
                )

                continue

            # =================================================
            # NORMAL FIELD
            # =================================================

            type_str = type_name(tag)

            # -------------------------------------------------
            # Has default?
            # -------------------------------------------------

            has_default = reader.read_u8()

            if has_default:

                value = decode_expression_value(
                    reader,
                    tag
                )

                print(
                    f"  {type_str} "
                    f"{field_name} = {value};"
                )

            else:

                print(
                    f"  {type_str} "
                    f"{field_name};"
                )

        print("}")

    # --------------------------------------------------------
    # Remaining data
    # --------------------------------------------------------

    if reader.has_more():

        remaining = reader.remaining()

        print()
        print(
            f"WARNING: {remaining} bytes remain "
            f"after polygon parsing."
        )

        preview = reader.data[
            reader.offset:
            reader.offset + min(64, remaining)
        ]

        print(
            "Remaining:",
            preview.hex(" ")
        )


# ============================================================
# AXB parser
# ============================================================

def parse_axb(filename):

    with open(filename, "rb") as f:
        data = f.read()

    print(
        f"File size: {len(data)} bytes "
        f"(0x{len(data):X})"
    )

    # --------------------------------------------------------
    # Minimum header
    # --------------------------------------------------------

    if len(data) < 32:

        raise ValueError(
            "File is too small to contain "
            "an AXB header"
        )

    # --------------------------------------------------------
    # Magic
    # --------------------------------------------------------

    if data[0:4] != b"AXIS":

        print("Invalid magic number")

        return

    # --------------------------------------------------------
    # Header
    # --------------------------------------------------------

    (
        major,
        minor,
        flags,
        meta_offset,
        meta_size,
        poly_offset,
        poly_size,
        poly_count,
    ) = struct.unpack_from(
        "<HHIIIIII",
        data,
        4
    )

    print(
        f"Header: Version "
        f"{major}.{minor}, "
        f"Flags: {flags}"
    )

    print(
        f"Sections: Metadata offset "
        f"{meta_offset} ({meta_size} bytes), "
        f"Polygon offset "
        f"{poly_offset} ({poly_size} bytes)"
    )

    print(
        f"Total Polygons: {poly_count}"
    )

    print("=" * 40)

    # --------------------------------------------------------
    # Validate metadata
    # --------------------------------------------------------

    if meta_offset + meta_size > len(data):

        raise ValueError(
            "Metadata section extends "
            "past end of file"
        )

    # --------------------------------------------------------
    # Validate polygons
    # --------------------------------------------------------

    if poly_offset + poly_size > len(data):

        raise ValueError(
            "Polygon section extends "
            "past end of file"
        )

    # --------------------------------------------------------
    # Parse metadata
    # --------------------------------------------------------

    parse_metadata(
        data,
        meta_offset,
        meta_size
    )

    # --------------------------------------------------------
    # Parse polygons
    # --------------------------------------------------------

    parse_polygon_section(
        data,
        poly_offset,
        poly_size,
        poly_count
    )


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":

    if len(sys.argv) < 2:

        print(
            "Usage: python3 dump_axb.py "
            "<file.axb>"
        )

        sys.exit(1)

    try:

        parse_axb(sys.argv[1])

    except Exception as e:

        print()
        print("=" * 40)
        print("PARSER ERROR")
        print("=" * 40)
        print(str(e))

        sys.exit(1)