#!/usr/bin/env python3

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

import sys
from elftools.elf.elffile import ELFFile
from elftools.elf.constants import SH_FLAGS

def load_elf_to_mem(mem, filename_in, verbose=False):
    max_addr = 0
    with open(filename_in, 'rb') as f:
        elffile = ELFFile(f)
        for section in elffile.iter_sections():
            if not (section['sh_flags'] & SH_FLAGS.SHF_ALLOC):
                continue
            addr_start = section['sh_addr']
            data=section.data()
            length = len(data)
            if verbose:
                print(f"{section.name:>12s}: start=0x{addr_start:08x}, length=0x{length:08x} ({length:>8,} bytes)")
            addr_end = addr_start+length
            if addr_end > len(mem):
                raise Exception("ELF file exceeds allocated memory size.")
            max_addr = max(max_addr, addr_end)
            mem[addr_start:addr_start+length] = data

    return max_addr

def dump_mem_to_file(mem, filename_out, bytes_per_line):
    cur_addr = 0
    with open(filename_out, "w") as f:
        while True:
            line_data = mem[cur_addr:cur_addr+bytes_per_line]
            if len(line_data) == bytes_per_line:
                f.write(bytes(reversed(line_data)).hex())
                f.write("\n")
            elif len(line_data) == 0:
                break
            else:
                raise Exception("Memory size seems not to be divisible by bytes_per_line.")
            cur_addr += bytes_per_line

def elf2mem(filename_in, filename_out, verbose=True):
    mem_size = 256*1024 # bytes
    bytes_per_line = 4

    mem = bytearray(mem_size)

    if verbose:
        info_str = f"Program info {filename_in}"
        print(info_str)
        print("-"*len(info_str))
    load_elf_to_mem(mem, filename_in, verbose)
    dump_mem_to_file(mem, filename_out, bytes_per_line)

def elfdelta(elf_in, elf_ref_in, filename_out):
    mem_size = 256*1024 # bytes
    bytes_per_line = 4

    mem = bytearray(mem_size)
    mem_ref = bytearray(mem_size)
    # max_addr: If  elf_ref_in contains stuff beyond the end of elf_in,
    # it is not overwritten with zeros (to save some time).
    max_addr = load_elf_to_mem(mem, elf_in)
    load_elf_to_mem(mem_ref, elf_ref_in)
    send_addr = True
    with open(filename_out, 'w') as f_out:
        for addr in range(0, max_addr, bytes_per_line):
            data = mem[addr:addr+4]
            data_ref = mem_ref[addr:addr+4]
            if data == data_ref:
                send_addr=True
            else:
                if send_addr:
                    f_out.write(f'addr {addr:08x}\n')
                f_out.write(f'data {bytes(reversed(data)).hex()}\n')
                send_addr=False

if __name__=="__main__":
    elf2mem(sys.argv[1], sys.argv[2])
