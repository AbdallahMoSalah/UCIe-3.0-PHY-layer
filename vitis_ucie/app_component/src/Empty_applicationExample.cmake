set(psu_ddr_0_memory_0 "0x0;0x7ff00000")
set(psu_ocm_ram_0_memory_0 "0xfffc0000;0x40000")
set(dst_bram_memory_0 "0xa0020000;0x2000")
set(src_bram_memory_1 "0xa0022000;0x2000")
set(DDR psu_ddr_0_memory_0)
set(CODE psu_ddr_0_memory_0)
set(DATA psu_ddr_0_memory_0)
set(TOTAL_MEM_CONTROLLERS "psu_ddr_0_memory_0;psu_ocm_ram_0_memory_0;dst_bram_memory_0;src_bram_memory_1")
set(MEMORY_SECTION "MEMORY
{
	psu_ddr_0_memory_0 : ORIGIN = 0x0, LENGTH = 0x7ff00000
	psu_ocm_ram_0_memory_0 : ORIGIN = 0xfffc0000, LENGTH = 0x40000
	dst_bram_memory_0 : ORIGIN = 0xa0020000, LENGTH = 0x2000
	src_bram_memory_1 : ORIGIN = 0xa0022000, LENGTH = 0x2000
}")
set(STACK_SIZE 0x2000)
set(HEAP_SIZE 0x2000)
