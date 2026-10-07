OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x00000000;
  .text : { *(.text.init) *(.text) *(.rodata*) }
  .data : { *(.data) *(.sdata) }
  .bss  : { *(.bss) *(.sbss) }
}
