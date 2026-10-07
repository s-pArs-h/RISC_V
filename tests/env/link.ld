/* Single 64 KiB memory starting at 0: code, then data. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text) }
  . = ALIGN(0x1000);
  .tohost    : { *(.tohost) }
  .data      : { *(.data) }
  .bss       : { *(.bss) }
  _end = .;
}
