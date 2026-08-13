/*==============================================================================
 * sections.lds
 * TinyRISC-TinyML -- linker script for a single unified instruction+data
 * RAM (no separate flash -- unlike picosoc's reference design, this
 * project has no external flash; soc_top.v (Phase 6) will instantiate one
 * synchronous-RAM block for both program and data, initialized directly
 * from this firmware's memory image via $readmemh in simulation / a BRAM
 * init file in Vivado).
 *
 * RAM_SIZE: 32 KiB placeholder. MUST be <= the actual depth of the RAM
 * soc_top.v instantiates in Phase 6 -- if that BRAM ends up smaller,
 * reduce this to match, or the linker will happily place code past the
 * end of real memory with no error until you notice it doesn't run.
 *============================================================================*/

MEMORY {
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x8000 /* 32 KiB */
}

SECTIONS {
    .text : {
        . = ALIGN(4);
        *(.text.start) /* start.S's entry point goes first */
        *(.text)
        *(.text*)
        . = ALIGN(4);
    } > ram

    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
    } > ram

    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } > ram

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > ram

    /* Stack grows down from the top of RAM. No heap is used by this
     * project (no malloc anywhere in software/src/) so none is reserved. */
    _stack_top = ORIGIN(ram) + LENGTH(ram);
}
