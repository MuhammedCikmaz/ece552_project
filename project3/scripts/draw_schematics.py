#!/usr/bin/env python3
"""Generate editable SVG schematics and the seven submission PDFs (CairoSVG)."""
from html import escape
from pathlib import Path
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
W, H = 2200, 1900
INK, MUTED, CONTROL, HOT = '#20334a', '#63758a', '#2166ad', '#e51a63'
SAMPLES = {
    '': ('Single-cycle RV32I processor', 'Complete datapath and control path'),
    'r': ('R-type: add x3, x1, x2', 'rs1 + rs2 -> x3; PC -> PC + 4'),
    'i': ('I-type: lw x3, 8(x1)', 'rs1 + I-immediate -> address; memory word -> x3; PC -> PC + 4'),
    's': ('S-type: sw x2, 12(x1)', 'rs1 + S-immediate -> address; rs2 -> memory; PC -> PC + 4'),
    'b': ('B-type: beq x1, x2, +16 (taken)', 'Compare rs1 and rs2; PC + B-immediate -> next PC; no register write'),
    'u': ('U-type: auipc x3, 0x12345', 'PC + U-immediate -> x3; PC -> PC + 4'),
    'j': ('J-type: jal x1, +16', 'PC + J-immediate -> next PC; PC + 4 -> x1'),
}


class Drawing:
    def __init__(self, kind):
        self.kind = kind
        self.parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
                      '<rect width="100%" height="100%" fill="white"/>']

    def text(self, x, y, value, size=17, color=INK, bold=False, anchor='start'):
        weight = '700' if bold else '400'
        self.parts.append(f'<text x="{x}" y="{y}" font-family="DejaVu Sans, sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{escape(value)}</text>')

    def active(self, tags):
        return bool(self.kind and self.kind in tags)

    def box(self, x, y, w, h, title, lines=(), tags='', sequential=False, external=False):
        c = HOT if self.active(tags) else INK
        fill = '#fff0f5' if self.active(tags) else ('#f1f5f9' if external else '#f7faff')
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="{fill}" stroke="{c}" stroke-width="2.5"/>')
        self.text(x+w/2, y+29, title, min(19, (w-20)/(len(title)*0.59)), c, True, 'middle')
        for n, line in enumerate(lines):
            self.text(x+15, y+56+n*24, line, min(16, (w-25)/(len(line)*0.57)))
        if sequential:
            self.parts.append(f'<path d="M {x+w/2-9} {y+h} l 9 -13 l 9 13" fill="none" stroke="{c}" stroke-width="2"/>')

    def wire(self, points, label='', tags='', control=False, label_at=None):
        c = HOT if self.active(tags) else (CONTROL if control else MUTED)
        dash = 'stroke-dasharray="7 5"' if control else ''
        path = ' '.join(f'{x},{y}' for x,y in points)
        self.parts.append(f'<polyline points="{path}" fill="none" stroke="{c}" stroke-width="{3.5 if self.active(tags) else 2}" {dash}/>')
        x,y=points[-1]; px,py=points[-2]
        dx,dy=x-px,y-py; norm=max(abs(dx),abs(dy),1); dx,dy=dx/norm,dy/norm
        self.parts.append(f'<polygon points="{x},{y} {x-10*dx+4*dy},{y-10*dy-4*dx} {x-10*dx-4*dy},{y-10*dy+4*dx}" fill="{c}"/>')
        if label:
            lx,ly=label_at or (points[0][0]+8,points[0][1]-9)
            self.text(lx,ly,label,15,c)

    def netin(self, x, y, label, tags='', control=False, length=100):
        self.wire([(x-length,y),(x,y)],label,tags,control,(x-length,y-8))

    def save(self, name):
        svg='\n'.join(self.parts+['</svg>'])
        (ROOT/'schematics'/f'{name}.svg').write_text(svg)
        cairosvg.svg2pdf(bytestring=svg.encode(),write_to=str(ROOT/f'{name}.pdf'))


def draw(kind):
    d=Drawing(kind)
    title,description=SAMPLES[kind]
    d.text(65,55,title,32,bold=True)
    d.text(65,90,description,20,color=HOT if kind else MUTED)
    d.text(2130,55,'ECE 552 / PROJECT 3',19,color=MUTED,anchor='end')
    d.box(70,490,150,110,'PC [31:0]',['reset: RESET_ADDR'],tags='risbuj',sequential=True)
    d.box(300,490,200,110,'Instruction memory',['external: tb.v','combinational read'],tags='risbuj',external=True)
    d.box(620,440,240,230,'Register file / rf.v',['32 x 32; x0 = 0','two async read ports','one sync write port','BYPASS_EN = 0','clk [1], rst [1]'],tags='risbj',sequential=True)
    d.box(620,350,240,65,'Source-address muxes',['rs1/rs2 or 5\'d0'],tags='risb')
    d.box(620,740,240,100,'Immediate / imm.v',['I / S / B: sign extend','U: <<12; J: sign extend'],tags='isbuj')
    d.box(600,150,460,180,'Decoder / decode.v',['opcode [6:0], funct3 [2:0], funct7 [6:0]','Checks legal instruction encodings','format [5:0]; use_rs1/use_rs2 [1 each]','Control outputs: see table below','ebreak [1], illegal [1]'],tags='risbuj')
    d.box(1010,440,100,85,'A mux',['rs1 / PC'],tags='risbu')
    d.box(1010,610,100,85,'B mux',['rs2 / imm'],tags='risbu')
    d.box(1210,455,190,240,'ALU / alu.v',['add/sub, shifts, logic','signed/unsigned SLT','result [31:0]','eq [1], lt [1]','opsel [2:0]','sub, unsigned, arith [1]'],tags='risbu')
    d.box(1510,425,290,110,'Writeback mux [31:0]',['00: ALU   01: load_value','10: PC+4  11: immediate'],tags='riuj')
    d.box(1510,635,290,225,'Load/store unit / lsu.v',['effective address [31:0]','store value = rs2 [31:0]','funct3 [2:0] selects size/sign','align address; select lanes','load: extract + sign/zero extend','store: position bytes in lanes','misaligned [1] -> trap logic'],tags='is')
    d.box(1900,635,230,225,'Data memory',['external: tb.v','masked async read','masked sync write','clk [1]'],tags='is',sequential=True,external=True)
    d.box(300,270,200,80,'PC + 4 adder',['pc4 [31:0]'],tags='risuj')
    d.box(1210,160,220,90,'Target adder',['pc_target = PC + imm','[31:0]'],tags='bj')
    d.box(1510,255,140,100,'Branch test',['eq / ~eq','lt / ~lt'],tags='b')
    d.box(1690,150,440,195,'Next-PC / trap control',['normal: pc4 / pc_target / JALR target','JALR target = {alu_result[31:1], 0}','trap: illegal OR misaligned data/target','trap -> pc4, suppress all writes','ebreak or halted -> hold PC','next_pc [31:0]; trap [1]; active [1]'],tags='risbuj')
    d.box(70,750,150,100,'Halted [1]',['reset: 0','set on ebreak'],sequential=True)

    d.wire([(220,540),(300,540)],'PC [31:0]','risbuj',label_at=(220,475))
    d.wire([(250,540),(250,310),(300,310)],'PC [31:0]','risuj',label_at=(255,380))
    d.wire([(500,540),(550,540),(550,370),(600,370),(600,235)],'inst [31:0]','risbuj',label_at=(355,395))
    d.wire([(550,370),(620,370)],'inst [31:0]','risb',label_at=(440,350))
    d.wire([(740,415),(740,440)],'rs1/rs2 [4:0]','risb',label_at=(755,433))
    d.wire([(550,540),(550,790),(620,790)],'inst [31:0]','isbuj',label_at=(415,735))
    d.wire([(860,480),(1010,480)],'rs1 [31:0]','risb')
    d.wire([(860,635),(1010,635)],'rs2 [31:0]','rb')
    d.wire([(860,790),(950,790),(950,675),(1010,675)],'imm [31:0]','isu',label_at=(870,815))
    d.netin(1010,510,'PC [31:0]','u',length=110)
    d.wire([(1110,480),(1210,480)],'A [31:0]','risbu')
    d.wire([(1110,655),(1210,655)],'B [31:0]','risbu')
    d.wire([(1400,480),(1510,480)],'result [31:0]','ru',label_at=(1405,455))
    d.wire([(1460,480),(1460,680),(1510,680)],'EA [31:0]','is',label_at=(1435,600))
    d.wire([(1400,560),(1475,560),(1475,305),(1510,305)],'eq, lt [1 each]','b',label_at=(1315,365))
    d.netin(1510,340,'funct3 [2:0]','b',control=True,length=110)
    d.wire([(1650,300),(1670,300),(1670,275),(1690,275)],'taken [1]','b',label_at=(1510,385))
    d.wire([(1430,200),(1690,200)],'pc_target [31:0]','bj')
    d.netin(1210,190,'PC [31:0]','bj',length=120)
    d.netin(1210,230,'imm [31:0]','bj',length=120)
    d.wire([(500,310),(530,310)],'pc4 [31:0]','risuj',label_at=(320,250))
    d.wire([(1900,150),(1900,115),(35,115),(35,565),(70,565)],'next_pc [31:0]','risbuj',label_at=(1160,105))
    d.wire([(1800,480),(1840,480),(1840,900),(590,900),(590,635),(620,635)],'wb_data [31:0]','riuj',label_at=(1050,890))
    d.wire([(1770,390),(1770,425)],'pc4 / imm [31:0]','j',label_at=(1710,380))
    d.wire([(1620,635),(1620,535)],'load_value [31:0]','i',label_at=(1635,580))
    d.wire([(1800,680),(1900,680)],'addr [31:0]','is',label_at=(1800,663))
    d.wire([(1800,730),(1900,730)],'wdata [31:0]','s',label_at=(1800,714))
    d.wire([(1800,780),(1900,780)],'mask [3:0]','is',label_at=(1800,764))
    d.wire([(1900,830),(1800,830)],'rdata [31:0]','i',label_at=(1805,815))
    d.netin(1510,745,'rs2 [31:0]','s',length=125)
    d.netin(1510,800,'funct3 [2:0]','is',control=True,length=125)
    d.netin(1900,875,'ren / wen [1 each]','is',control=True,length=180)
    d.wire([(1900,875),(2000,875),(2000,860)],tags='is',control=True)

    # Named control nets keep the drawing legible. Identical labels are connected.
    d.netin(1010,420,'alu_pc [1]','u',control=True,length=110)
    d.wire([(1010,420),(1055,420),(1055,440)],tags='u',control=True)
    d.netin(1010,590,'alu_imm [1]','isu',control=True,length=110)
    d.wire([(1010,590),(1055,590),(1055,610)],tags='isu',control=True)
    d.netin(1210,425,'ALU ctrl [6]','risbu',control=True,length=100)
    d.wire([(1210,425),(1300,425),(1300,455)],tags='risbu',control=True)
    d.netin(1510,405,'wb_sel [1:0]','riuj',control=True,length=125)
    d.wire([(1510,405),(1610,405),(1610,425)],tags='riuj',control=True)
    d.netin(620,460,'rd [4:0], rd_wen [1]','riuj',control=True,length=180)
    d.netin(620,765,'format [5:0]','isbuj',control=True,length=155)
    d.text(70,710,'clk [1], rst [1] -> PC, RF, halted',16,color=CONTROL)
    d.text(70,875,'active = ~rst & ~halted',16)
    d.text(70,920,'Triangles mark clocked state. Gray memory blocks are external to hart. Unmarked blocks are combinational.',18)
    d.text(70,950,'Blue dashed wires are control. Matching named nets are electrically connected; bus widths are shown in brackets.',18,color=CONTROL)
    d.text(70,980,'Bright pink highlights the sample instruction path, including writeback and PC update.' if kind else 'Retire outputs observe this cycle\'s instruction, source operands, writeback, PC and next PC; omitted from schematic per assignment.',18,color=HOT if kind else MUTED)

    d.box(65,1015,1065,500,'Decoder outputs and selection logic',[])
    columns=[85,270,370,510,670,815,955]
    headings=['Instruction','format','ALU A / B','ALU op','wb_sel','RegW','Memory / PC']
    for x,s in zip(columns,headings): d.text(x,1080,s,16,bold=True)
    rows=[
        ['R arithmetic','000001','rs1 / rs2','funct3','00','1','none / pc4'],
        ['I arithmetic','000010','rs1 / imm','funct3','00','1','none / pc4'],
        ['Load','000010','rs1 / imm','ADD','01','1','read / pc4'],
        ['Store','000100','rs1 / imm','ADD','--','0','write / pc4'],
        ['Branch','001000','rs1 / rs2','compare','--','0','none / target*'],
        ['LUI','010000','unused','unused','11','1','none / pc4'],
        ['AUIPC','010000','PC / imm','ADD','00','1','none / pc4'],
        ['JAL','100000','unused','unused','10','1','none / target'],
        ['JALR','000010','rs1 / imm','ADD','10','1','none / ALU&~1'],
        ['EBREAK / FENCE','000001','unused','unused','--','0','hold / pc4'],
    ]
    for n,row in enumerate(rows):
        for x,s in zip(columns,row): d.text(x,1110+28*n,s,15)
    for n,s in enumerate([
        '* branch target selected only if the comparison is true; otherwise pc4.',
        'sub: R-type SUB only; arith: SRA/SRAI; unsigned: SLTU/SLTIU or BLTU/BGEU.',
        'use_rs1/rs2 [1 each] select inst[19:15]/inst[24:20], or 5\'d0, into RF.',
        'rd_wen = RegW & active & ~trap & (rd != 0); rd = inst[11:7].',
        'ren/wen = load/store & active & ~trap; illegal encodings have no side effects.',
    ]): d.text(85,1410+n*21,s,15)

    d.box(1160,1015,970,500,'Memory lanes, branch conditions, and state control',[])
    details=[
        'EA [31:0] = rs1 + immediate; offset [1:0] = EA[1:0].',
        'o_dmem_addr [31:0] = {EA[31:2], 2\'b00}.',
        'Byte mask [3:0]: offset 0/1/2/3 -> 0001/0010/0100/1000.',
        'Half mask [3:0]: offset 0/2 -> 0011/1100; word mask = 1111.',
        'Store mux [31:0]: rs2 << 0/8/16/24 selected by offset [1:0].',
        'Load mux [31:0]: rdata >> 0/8/16/24 selected by offset [1:0].',
        'LB/LH sign-extend low 8/16 bits; LBU/LHU zero-extend; LW passes 32 bits.',
        'All lane shifts use constant wiring and muxes, never variable shift operators.',
        'misaligned [1] = half & EA[0] OR word & (EA[1:0] != 0).',
        'BEQ/BNE select eq/~eq; BLT/BLTU select lt; BGE/BGEU select ~lt.',
        'Jump or taken branch traps if target[1:0] != 0 (after JALR clears bit 0).',
        'Trap policy: suppress register/memory writes; continue at pc4 (no CSRs).',
        'EBREAK: assert halt this cycle; hold PC; latch halted on rising clock.',
        'Halted: no memory access, register writes or retirement until reset.',
        'Synchronous reset: PC <- RESET_ADDR; RF <- 0; halted <- 0.',
    ]
    for n,s in enumerate(details): d.text(1180,1080+n*27,s,16)
    d.box(65,1540,1065,285,'Named control nets: source -> destination (port connections)',[])
    controls=[
        'decode.use_rs1/use_rs2 [1 each] -> source-address mux selects.',
        'decode.format [5:0] -> imm.i_format; inst [31:0] -> decode.i_inst / imm.i_inst.',
        'decode.alu_pc / alu_imm [1 each] -> A / B mux selects.',
        'decode.alu_op [2:0], sub/unsigned/arith [1 each] -> ALU ctrl [5:0].',
        'decode.wb_sel [1:0] -> writeback mux; decode.reg_write [1] -> rd_wen gate.',
        'decode.load/store [1 each] -> ren/wen gates and data-alignment trap gate.',
        'decode.branch/jal/jalr [1 each] -> redirect / target mux in next-PC logic.',
        'decode.ebreak [1] -> halted set input and next-PC hold select.',
        'decode.illegal [1] -> trap OR; trap [1] -> write/access gates and next-PC mux.',
    ]
    for n,s in enumerate(controls): d.text(85,1600+n*24,s,16)
    d.box(1160,1540,970,285,'Named data nets and next-PC mux inputs',[])
    nets=[
        'PC [31:0] -> instruction address, PC+4 adder, target adder, ALU A mux.',
        'imm [31:0] -> ALU B mux, target adder, writeback input 11.',
        'pc4 [31:0] -> next-PC default and writeback input 10.',
        'alu_result [31:0] -> JALR target clear-bit-0 wiring, LSU, writeback input 00.',
        'rs2_data [31:0] -> LSU store-data input and ALU B mux.',
        'LSU.misaligned [1] / target[1:0] / PC[1:0] -> trap detection.',
        'redirect [1] = jal | jalr | (branch & branch_condition).',
        'next_pc = (halted | ebreak) ? PC : trap ? pc4 : redirect ? target : pc4.',
        'halted_next [1] = halted | ebreak; clk/rst [1 each] -> all state elements.',
    ]
    for n,s in enumerate(nets): d.text(1180,1600+n*24,s,16)
    d.text(65,1865,'Source: schematics/*.svg (editable in Inkscape). Implementation: rtl/{hart,decode,alu,rf,imm,lsu}.v',15,color=MUTED)
    d.save('schematic' if not kind else f'{kind}_type_schematic')


if __name__=='__main__':
    (ROOT/'schematics').mkdir(exist_ok=True)
    for kind in SAMPLES: draw(kind)
    print('Generated seven SVG schematics and seven PDFs.')
