
SECTIONS
{
  . = 0x80000000;
  .text : { /* This is the output section .text */
    *(.text) /* This matches all .text sections in all input files */
    *(.text*) /* This matches all .text* sections in all input files */
  }
}
