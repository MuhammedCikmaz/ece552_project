#!/usr/bin/env python3
"""Run supplied assembly tests and compare RTL against an independent RV32I model.

Requires Icarus and GNU RISC-V binutils. Override tool names with IVERILOG,
IVERILOG_FLAGS, VVP and RISCV_PREFIX. Only Python's standard library is used.
"""
import collections
import json
import os
from pathlib import Path
import random
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build' / 'tests'
MASK = 0xffffffff
COVERAGE = collections.Counter()


def run(args, **kwargs):
    result = subprocess.run([str(a) for a in args], text=True, capture_output=True,
                            timeout=45, **kwargs)
    if result.returncode:
        raise AssertionError(f"Command failed: {args}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def sx(value, width):
    return (value & ((1 << (width-1))-1)) - (value & (1 << (width-1)))


def r(f3, rd, a, b, f7=0):
    return f7 << 25 | b << 20 | a << 15 | f3 << 12 | rd << 7 | 0x33


def i(f3, rd, a, imm, op=0x13):
    return (imm & 0xfff) << 20 | a << 15 | f3 << 12 | rd << 7 | op


def s(f3, a, b, imm):
    imm &= 0xfff
    return (imm >> 5) << 25 | b << 20 | a << 15 | f3 << 12 | (imm & 31) << 7 | 0x23


def b(f3, a, c, imm):
    imm &= 0x1fff
    return ((imm >> 12) << 31 | ((imm >> 5) & 63) << 25 | c << 20 |
            a << 15 | f3 << 12 | ((imm >> 1) & 15) << 8 | ((imm >> 11) & 1) << 7 | 0x63)


def j(rd, imm):
    imm &= 0x1fffff
    return ((imm >> 20) << 31 | ((imm >> 1) & 1023) << 21 |
            ((imm >> 11) & 1) << 20 | ((imm >> 12) & 255) << 12 | rd << 7 | 0x6f)


def u(rd, imm, op=0x37):
    return imm & 0xfffff000 | rd << 7 | op


def constant(rd, value):
    value &= MASK
    upper = (value + 0x800) & 0xfffff000
    return [u(rd, upper), i(0, rd, rd, sx(value & 0xfff, 12))]


def reference(words, start=0):
    """Architectural model: decode instruction behavior, not RTL control signals."""
    regs = [0]*32
    mem = bytearray((n*37+11) & 255 for n in range(65536))
    pc = start
    trace = []
    for cycle in range(100000):
        if pc % 4 or not (0 <= (pc-start)//4 < len(words)):
            raise AssertionError(f'Model fetch outside program: {pc:08x}')
        ins = words[(pc-start)//4]
        op, rd, f3 = ins & 127, (ins >> 7) & 31, (ins >> 12) & 7
        a, c, f7 = (ins >> 15) & 31, (ins >> 20) & 31, ins >> 25
        av, cv = regs[a], regs[c]
        imm = sx(ins >> 20, 12)
        nxt = (pc+4) & MASK
        ra = rc = dest = value = trap = halt = ren = wen = addr = lanes = wdata = 0
        name = 'illegal'
        try:
            if op in (0x33, 0x13):
                ra, rc, dest = a, c if op == 0x33 else 0, rd
                rhs = cv if op == 0x33 else imm & MASK
                sub = op == 0x33 and f7 == 32 and f3 == 0
                arithmetic = f3 == 5 and f7 == 32
                if op == 0x33:
                    assert f7 == 0 or (f7 == 32 and f3 in (0, 5))
                elif f3 in (1, 5):
                    assert f7 == 0 or (f3 == 5 and f7 == 32)
                if f3 == 0: value, name = (av-rhs, 'sub') if sub else (av+rhs, 'add')
                elif f3 == 1: value, name = av << (rhs & 31), 'sll'
                elif f3 == 2: value, name = int(sx(av, 32) < sx(rhs, 32)), 'slt'
                elif f3 == 3: value, name = int(av < rhs), 'sltu'
                elif f3 == 4: value, name = av ^ rhs, 'xor'
                elif f3 == 5:
                    value, name = ((sx(av, 32) >> (rhs & 31), 'sra') if arithmetic
                                   else (av >> (rhs & 31), 'srl'))
                elif f3 == 6: value, name = av | rhs, 'or'
                else: value, name = av & rhs, 'and'
                if op == 0x13: name = 'sltiu' if name == 'sltu' else name+'i'
            elif op in (0x37, 0x17):
                dest = rd
                value = (ins & 0xfffff000) + (pc if op == 0x17 else 0)
                name = 'auipc' if op == 0x17 else 'lui'
            elif op == 0x63:
                ra, rc = a, c
                assert f3 in (0, 1, 4, 5, 6, 7)
                cond = {0: av == cv, 1: av != cv, 4: sx(av, 32) < sx(cv, 32),
                        5: sx(av, 32) >= sx(cv, 32), 6: av < cv, 7: av >= cv}[f3]
                offset = sx(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) |
                            (((ins >> 25) & 63) << 5) | (((ins >> 8) & 15) << 1), 13)
                name = {0:'beq',1:'bne',4:'blt',5:'bge',6:'bltu',7:'bgeu'}[f3]
                COVERAGE[name + ('_taken' if cond else '_not_taken')] += 1
                if cond:
                    nxt = (pc+offset) & MASK
                    assert nxt % 4 == 0
            elif op in (0x6f, 0x67):
                dest, value = rd, pc+4
                if op == 0x6f:
                    offset = sx(((ins >> 31) << 20) | (((ins >> 12) & 255) << 12) |
                                (((ins >> 20) & 1) << 11) | (((ins >> 21) & 1023) << 1), 21)
                    nxt, name = (pc+offset) & MASK, 'jal'
                else:
                    ra = a
                    assert f3 == 0
                    nxt, name = (av+imm) & 0xfffffffe, 'jalr'
                assert nxt % 4 == 0
            elif op in (0x03, 0x23):
                ra, rc = a, c if op == 0x23 else 0
                if op == 0x23:
                    assert f3 in (0, 1, 2)
                    imm = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
                else:
                    assert f3 in (0, 1, 2, 4, 5)
                size = 1 << (f3 & 3)
                ea = (av + imm) & MASK
                assert ea % size == 0
                if ea+size > len(mem): raise RuntimeError(f'Model data address out of bounds: {ea:x}')
                addr, lanes = ea & ~3, ((1 << size)-1) << (ea & 3)
                if op == 0x23:
                    wen, wdata = 1, (cv << (8*(ea & 3))) & MASK
                    for index in range(size): mem[ea+index] = (cv >> (8*index)) & 255
                    name = {0:'sb',1:'sh',2:'sw'}[f3]
                else:
                    ren, dest = 1, rd
                    value = int.from_bytes(mem[ea:ea+size], 'little')
                    if f3 < 4: value = sx(value, size*8)
                    name = {0:'lb',1:'lh',2:'lw',4:'lbu',5:'lhu'}[f3]
            elif ins == 0x00100073:
                halt, nxt, name = 1, pc, 'ebreak'
            elif op == 0x0f and f3 == 0:
                name = 'fence'
            else:
                # Unsupported instruction fields still drive read addresses in
                # recognized opcode classes; these do not change architecture.
                raise AssertionError('illegal')
        except AssertionError:
            trap, dest, ren, wen, nxt = 1, 0, 0, 0, (pc+4) & MASK
            name = 'trap'
        value &= MASK
        row = dict(pc=pc, inst=ins, rs1=ra, rs1_data=regs[ra], rs2=rc,
                   rs2_data=regs[rc], rd=dest, rd_data=value, next_pc=nxt,
                   trap=trap, halt=halt, ren=ren, wen=wen, addr=addr, mask=lanes, wdata=wdata)
        trace.append(row)
        if dest: regs[dest] = value
        COVERAGE[name] += 1
        if halt: return trace, regs
        pc = nxt
    raise AssertionError('Reference did not halt')


def write_mem(words, path, start=0):
    data = b'\0'*start + b''.join(w.to_bytes(4,'little') for w in words)
    path.write_text('\n'.join(' '.join(f'{b:02x}' for b in data[n:n+4]) for n in range(0,len(data),4))+'\n')


def compile_tb(name, tb, reset=0):
    exe = BUILD / f'{name}.vvp'
    command = [os.environ.get('IVERILOG','iverilog')]
    command += shlex.split(os.environ.get('IVERILOG_FLAGS',''))
    command += ['-g2005', '-s', name, '-o', exe]
    if name == 'differential_tb': command += [f'-P{name}.RESET_ADDR={reset}']
    run(command + sorted((ROOT/'rtl').glob('*.v')) + [tb])
    return exe


def compare(name, words, exe, start=0, restart=False):
    program = BUILD / f'{name}.mem'
    write_mem(words, program, start)
    expected, regs = reference(words, start)
    out = run([os.environ.get('VVP','vvp'),exe,f'+program={program}'] + (['+restart'] if restart else []))
    (BUILD/f'{name}.trace').write_text(out)
    actual = [line.split()[1:] for line in out.splitlines() if line.startswith('RET ')]
    if restart: expected = expected*2
    assert 'HALT_OK' in out and len(actual) == len(expected), (name,len(actual),len(expected),out[-1000:])
    fields = list(expected[0])
    for cycle,(tokens,want) in enumerate(zip(actual,expected)):
        for field,token in zip(fields,tokens):
            if field == 'rd_data' and want['rd'] == 0: continue
            if field in ('addr','mask') and not (want['ren'] or want['wen']): continue
            if field == 'wdata' and not want['wen']: continue
            try: got=int(token,16)
            except ValueError: raise AssertionError(f'{name} cycle {cycle}: unknown {field}={token}')
            assert got == want[field], (f'{name} cycle {cycle} PC={want["pc"]:08x} '
                                        f'inst={want["inst"]:08x} {field}: RTL={got:08x}, model={want[field]:08x}')
    print(f'PASS {name}: {len(expected)} retirements')
    return len(expected), regs


def directed():
    words=[]
    values=[0,1,0x7fffffff,0x80000000,0xffffffff,0x80000001,0x55555555,0xaaaaaaaa]
    for av in values:
        for cv in values:
            words += constant(1,av)+constant(2,cv)
            for f3 in range(8): words.append(r(f3,3,1,2))
            words += [r(0,3,1,2,32),r(5,3,1,2,32)]
    for av in values:
        words += constant(1,av)
        for amount in range(32):
            words += [i(1,3,1,amount),i(5,3,1,amount),i(5,3,1,0x400+amount)]
        for imm in [-2048,-1024,-1,0,1,1023,2047]:
            for f3 in [0,2,3,4,6,7]: words.append(i(f3,3,1,imm))
    words += [i(0,0,0,77),i(0,1,0,9),i(0,1,1,-4),r(0,1,1,1)]
    words += [u(3,0x12345000,0x17),u(0,0xfffff000),u(3,0xfffff000)]
    # Every lane, sign extension, and partial-store preservation after SW.
    words += constant(20,0x400)+constant(2,0x89abcdef)
    words += [s(2,20,2,0)]
    for off in range(4):
        words += [i(0,3,20,off,3),i(4,4,20,off,3)]
    for off in [0,2]: words += [i(1,3,20,off,3),i(5,4,20,off,3)]
    for off in range(4):
        words += [s(0,20,2,off),i(2,3,20,0,3),i(0,2,2,-1)]
    for off in [0,2]: words += [s(1,20,2,off),i(2,3,20,0,3)]
    words += [s(2,20,2,-4),i(2,3,20,-4,3),i(2,0,20,-4,3)]
    # All branch conditions, taken and not taken, including signed extremes.
    for av,cv in [(0,0),(0,1),(1,0),(0x80000000,1),(0xffffffff,0),(0x7fffffff,0x80000000)]:
        words += constant(1,av)+constant(2,cv)
        for f3 in [0,1,4,5,6,7]: words += [b(f3,1,2,8),i(0,3,3,1)]
    # A backward loop and a subroutine: link and return.
    words += [i(0,1,0,4),i(0,1,1,-1),b(1,1,0,-4)]
    words += [j(5,12),j(0,16),i(0,3,0,99),i(0,3,0,42),i(0,0,5,0,0x67)]
    words += [i(0,3,0,12)]
    # JALR reads old rs1 even when rd==rs1 and clears only target bit zero.
    target=(len(words)+4)*4
    words += constant(6,target+1)+[i(0,6,6,0,0x67),i(0,3,0,99),i(0,3,6,0)]
    words += [0x0000000f,0x00100073]
    return words


def long_control_flow():
    # Sparse code exercises nontrivial immediate fields and negative JAL.
    words=[i(0,0,0,0)]*4096
    words[0]=j(5,8192)
    words[2048]=j(6,-4096)
    words[1024]=b(0,0,0,2048)
    words[1536]=b(1,0,0,4094)  # Untaken, despite a misaligned target.
    words[1537]=i(0,7,0,123)
    words[1538]=0x00100073
    return words


def traps():
    words = constant(1,0x400)+constant(2,0xdeadbeef)
    words += [s(2,1,2,0)]
    # Misaligned load/store must neither write a register nor touch memory.
    for off in [1,2,3]: words += [i(2,3,1,off,3),s(2,1,2,off)]
    for off in [1,3]: words += [i(1,3,1,off,3),i(5,3,1,off,3),s(1,1,2,off)]
    words += [i(2,3,1,0,3)]
    words += [b(0,0,0,2),b(1,0,0,2),j(5,2)]
    words += constant(6,3)+[i(0,5,6,0,0x67)]
    words += [r(0,3,1,2,1),r(1,3,1,2,32),i(1,3,1,32),i(5,3,1,0x800)]
    words += [i(3,3,1,0,3),s(3,1,2,0),b(2,1,2,4),i(1,3,1,0,0x67)]
    words += [0xffffffff,0x00000000,0x00000073,0x00200073,0x00101073,0x0000100f,0x00100073]
    return words


def randomized(seed):
    rng=random.Random(seed)
    words=[]
    for reg in range(1,31): words+=constant(reg,rng.getrandbits(32))
    words+=constant(31,0x2000)
    for _ in range(1200):
        kind=rng.randrange(7)
        rd,a,c=[rng.randrange(31) for _ in range(3)]
        f3=rng.randrange(8)
        if kind==0: words.append(r(f3,rd,a,c,32 if f3 in (0,5) and rng.randrange(2) else 0))
        elif kind==1:
            imm=rng.randrange(-2048,2048)
            if f3==1: imm=rng.randrange(32)
            if f3==5: imm=rng.randrange(32)+rng.choice([0,1024])
            words.append(i(f3,rd,a,imm))
        elif kind==2: words.append(u(rd,rng.getrandbits(32),rng.choice([0x17,0x37])))
        elif kind==3:
            f3=rng.choice([0,1,2,4,5]); size=1<<(f3&3)
            off=rng.randrange(-128,128)//size*size
            words.append(i(f3,rd,31,off,3))
        elif kind==4:
            f3=rng.randrange(3); size=1<<f3
            words.append(s(f3,31,c,rng.randrange(-128,128)//size*size))
        elif kind==5: words += [b(rng.choice([0,1,4,5,6,7]),a,c,8),i(0,rd,a,1)]
        else: words += [j(rd,8),i(0,rd,a,1)]
    words.append(0x00100073)
    return words


def main():
    BUILD.mkdir(parents=True,exist_ok=True)
    exe=compile_tb('differential_tb',ROOT/'tests'/'differential_tb.v')
    stock=compile_tb('hart_tb',ROOT/'tb'/'tb.v')
    total=0; tests=0
    prefix=os.environ.get('RISCV_PREFIX','riscv64-unknown-elf-')
    for source in sorted((ROOT/'tests'/'asm').glob('*.asm')):
        obj=BUILD/f'{source.stem}.o'; binary=BUILD/f'{source.stem}.bin'
        run([prefix+'as','-march=rv32i','-mabi=ilp32',source,'-o',obj])
        run([prefix+'objcopy','-O','binary','-j','.text',obj,binary])
        data=binary.read_bytes()
        words=[int.from_bytes(data[n:n+4],'little') for n in range(0,len(data),4)]
        count,regs=compare(source.stem,words,exe)
        assert regs[10]==1, f'{source.stem}: assembly reported failure'
        total+=count; tests+=1
        # Also exercise the actual supplied testbench, unchanged.
        stock_dir=BUILD/source.stem; stock_dir.mkdir(exist_ok=True)
        write_mem(words+[0]*((1024-len(data))//4),stock_dir/'program.mem')
        output=run([os.environ.get('VVP','vvp'),stock],cwd=stock_dir)
        (stock_dir/'stock.trace').write_text(output)
        assert 'TRAP' not in output and 'did not halt' not in output
        assert re.search(r'w\[10\]=00000001',output)
    for name,words in [('directed',directed()),('long_control_flow',long_control_flow()),('traps',traps())]+[(f'random_{seed}',randomized(seed)) for seed in range(8)]:
        count,_=compare(name,words,exe); total+=count; tests+=1
    # Nonzero RESET_ADDR and reset after EBREAK must clear RF and halt state.
    exe=compile_tb('differential_tb',ROOT/'tests'/'differential_tb.v',reset=256)
    words=[i(0,1,1,1),u(2,0,0x17),i(0,0,0,42),i(0,3,0,0),0x00100073]
    count,_=compare('reset_restart',words,exe,start=256,restart=True)
    total+=count; tests+=1
    required={'add','sub','sll','slt','sltu','xor','srl','sra','or','and',
              'addi','slli','slti','sltiu','xori','srli','srai','ori','andi',
              'lui','auipc','jal','jalr','lb','lh','lw','lbu','lhu','sb','sh','sw','ebreak'}
    required|={op+suffix for op in ['beq','bne','blt','bge','bltu','bgeu'] for suffix in ['_taken','_not_taken']}
    assert not (required-COVERAGE.keys()), f'Missing coverage: {required-COVERAGE.keys()}'
    report=dict(tests=tests,retirements=total,supplied_tests=5,random_seeds=8,coverage=dict(sorted(COVERAGE.items())))
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'PASS: {tests} programs, {total} retirements; 5 supplied testbench runs; all required instruction families covered.')


if __name__=='__main__': main()
