import sys
from memory_layout import Sequence, MemoryRegion, DiscontinuityRegion
from memory_layout.renderers.svg import MLDRenderSVG

config_regs = [
    (0x00, 4, "PCIe Ext Cap Header"),
    (0x04, 4, "DVSEC Header 1"),
    (0x08, 2, "DVSEC Header 2"),
    (0x0A, 2, "Capability Descriptor"),
    (0x0C, 4, "UCIe Link Capability"),
    (0x10, 4, "UCIe Link Control"),
    (0x14, 4, "UCIe Link Status"),
    (0x18, 2, "Link Event Notif Ctrl"),
    (0x1A, 2, "Error Notif Ctrl"),
    (0x1C, 4, "Register Locator 0 Low"),
    (0x20, 4, "Register Locator 0 High"),
]

mmio_regs = [
    (0x1000, 4, "PHY Capability"),
    (0x1004, 4, "PHY Control"),
    (0x1008, 4, "PHY Status"),
    (0x100C, 4, "PHY Initialization and Debug"),
    (0x1010, 4, "Training Setup 1"),
    (0x1020, 4, "Training Setup 2"),
    (0x1030, 4, "Training Setup 3"),
    (0x1050, 4, "Training Setup 4"),
    (0x1060, 8, "Current Lane Map Module 0"),
    (0x1080, 4, "Error Log 0"),
    (0x1090, 4, "Error Log 1"),
    (0x1100, 8, "Runtime Link Test Control"),
    (0x1108, 4, "Runtime Link Test Status")
]

def hex25(addr):
    return f"0x{addr:07X}"

def size_str(size_bytes):
    return f"{size_bytes} B "

sequence = Sequence()
sequence.unit_size = 4
sequence.unit_height = 0.5
sequence.region_min_height = 0.6
sequence.region_max_height = 1.0
sequence.discontinuity_height = 1.5
sequence.region_width = 3.0
sequence.document_bgcolour = '#FFFFFF'

for i, (offset, size, name) in enumerate(config_regs):
    addr = 0x0000000 + offset
    region = MemoryRegion(addr, size)
    if i == 0:
        region.add_label("Config\nSpace\n(Bit 24=0)", ('el', 'ic'), colour='#000000')
    
    region.add_label(name, ('ic', 'ic'), colour='#000000')
    region.add_label(size_str(size), ('ir', 'ic'), colour='#000000')
    
    region.add_label(hex25(addr), ('er', 'ib'), colour='#000000')
        
    region.set_fill_colour('#CDE3ED')
    region.set_outline_colour('#2A6EBB')
    sequence.add_region(region)

for i, (offset, size, name) in enumerate(mmio_regs):
    addr = 0x1000000 + offset
    region = MemoryRegion(addr, size)
    if i == 0:
        region.add_label("MMIO\nSpace\n(Bit 24=1)", ('el', 'ic'), colour='#000000')
    
    region.add_label(name, ('ic', 'ic'), colour='#000000')
    region.add_label(size_str(size), ('ir', 'ic'), colour='#000000')
    
    region.add_label(hex25(addr), ('er', 'ib'), colour='#000000')
        
    region.set_fill_colour('#CDE3ED')
    region.set_outline_colour('#2A6EBB')
    sequence.add_region(region)

sequence.add_discontinuities(fill='#FFFFFF', outline='#2A6EBB', style='cut-out')

renderer = MLDRenderSVG('chapter9_reg_layout.svg')
renderer.render(sequence)
