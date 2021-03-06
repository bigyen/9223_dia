/*
 *  armboot - Startup Code for ARM926EJS CPU-core
 *
 *  Copyright (c) 2003  Texas Instruments
 *
 *  ----- Adapted for OMAP1610 from ARM925t code ------
 *
 *  Copyright (c) 2001	Marius Gr�ger <mag@sysgo.de>
 *  Copyright (c) 2002	Alex Z�pke <azu@sysgo.de>
 *  Copyright (c) 2002	Gary Jennejohn <gj@denx.de>
 *  Copyright (c) 2003	Richard Woodruff <r-woodruff2@ti.com>
 *  Copyright (c) 2003	Kshitij <kshitij@ti.com>
 *
 * See file CREDITS for list of people who contributed to this
 * project.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */


/*-----------------------------------------------------------------------
 * Stack sizes
 *
 * The stack sizes are set up in start.S using the settings below
 */
#define CONFIG_STACKSIZE        (128*1024)      /* regular stack */
#define CFG_ENV_SIZE		0x1000 /* Total Size of Environment Sector */
#define CFG_MALLOC_LEN		(CFG_ENV_SIZE + 128*1024)
#define CFG_GBL_DATA_SIZE	128	/* size in bytes reserved for initial data */

#ifndef CONFIG_ROM
#define CONFIG_USE_IRQ
#endif

#ifdef CONFIG_USE_IRQ
#define CONFIG_STACKSIZE_IRQ    (4*1024)        /* IRQ stack */
#define CONFIG_STACKSIZE_FIQ    (4*1024)        /* FIQ stack */
#endif

/*-----------------------------------------------------------------------


/ *************************************************************************
 *
 * Jump vector table as in table 3.1 in [1]
 *
 *************************************************************************
 */

.section ".init.text","ax"

.globl _start
_start:
	b	reset
	ldr	pc, _undefined_instruction
	ldr	pc, _software_interrupt
	ldr	pc, _prefetch_abort
	ldr	pc, _data_abort
	ldr	pc, _not_used
	ldr	pc, _irq
	ldr	pc, _fiq

_undefined_instruction:
	.word undefined_instruction
_software_interrupt:
	.word software_interrupt
_prefetch_abort:
	.word prefetch_abort
_data_abort:
	.word data_abort
_not_used:
	.word not_used
_irq:
	.word irq
_fiq:
	.word fiq

	.balignl 16,0xdeadbeef

/*
 *************************************************************************
 *
 * Startup Code (reset vector)
 *
 * do important init only if we don't start from memory!
 * setup Memory and board specific bits prior to relocation.
 * relocate armboot to ram
 * setup stack
 *
 *************************************************************************
 */

_TEXT_BASE:
	.word	TEXT_BASE

.globl _armboot_start
_armboot_start:
	.word _start

/*
 * These are defined in the board-specific linker script.
 */
.globl _bss_start
_bss_start:
	.word __bss_start

.globl _bss_end
_bss_end:
	.word __bss_end

#ifdef CONFIG_USE_IRQ

/* IRQ stack memory (calculated at run-time) */
.globl IRQ_STACK_START
IRQ_STACK_START:
	.word __irq_stack_start

/* IRQ stack memory (calculated at run-time) */
.globl FIQ_STACK_START
FIQ_STACK_START:
	.word __fiq_stack_start
#endif


.globl STACK_START
STACK_START:
	.word __stack_start

#ifndef CONFIG_ROM
.globl TLB_MAP_START
TLB_MAP_START:
	.word __map_start
#	.word __tlb_map_start
#endif

/*
 * the actual reset code
 */

reset:
	/*
	 * set the cpu to SVC32 mode
	 */
	mrs	r0,cpsr
	bic	r0,r0,#0x1f
	orr	r0,r0,#0xd3
	msr	cpsr,r0

	/*
	 * we do sys-critical inits only at reboot,
	 * not when booting from ram!
	 */
#ifndef CONFIG_ROM
	ldr	r0, TLB_MAP_START
	mcr	p15, 0, r0, c2, c0, 0	/* set translation table base */
	mov	r0, #0x3
	mcr	p15, 0, r0, c3, c0, 0	/* Only Domain 0 can be accessed */
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * Enable MMU stuff and caches @ARM B3-23
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002300	/* clear bits 13, 9:8 (--V- --RS) */
	bic	r0, r0, #0x00000087	/* clear bits 7, 2:0 (B--- -CAM) */
	orr	r0, r0, #0x00000002	/* set bit 1 (A) Align */
	bic	r0, r0, #0x00001000	/* clear bit 12 (I) I-Cache */

	orr	r0, r0, #0x00001000	/* set bit 12 (I) I-Cache */
 	orr	r0, r0, #0x00000004	/* set bit 2  (C) D-Cache */
	orr	r0, r0, #0x00000001	/* set bit 0  MMU:enable */
	mcr	p15, 0, r0, c1, c0, 0
#endif

#ifdef CONFIG_INIT_CRITICAL
	bl	cpu_init_crit
#endif

#relocate:				/* relocate U-Boot to RAM	    */
#	adr	r0, _start		/* r0 <- current position of code   */
#	ldr	r1, _TEXT_BASE		/* test if we run from flash or RAM */
#	cmp     r0, r1                  /* don't reloc during debug         */
#	beq     stack_setup
#
#	ldr	r2, _armboot_start
#	ldr	r3, _bss_start
#	sub	r2, r3, r2		/* r2 <- size of armboot            */
#	add	r2, r0, r2		/* r2 <- source end address         */
#
#copy_loop:
#	ldmia	r0!, {r3-r10}		/* copy from source address [r0]    */
#	stmia	r1!, {r3-r10}		/* copy to   target address [r1]    */
#	cmp	r0, r2			/* until source end addreee [r2]    */
#	ble	copy_loop
#
#	/* Set up the stack						    */
stack_setup:
#if 0
	ldr	r0, _TEXT_BASE		/* upper 128 KiB: relocated uboot   */
	sub	r0, r0, #CFG_MALLOC_LEN	/* malloc area                      */
	sub	r0, r0, #CFG_GBL_DATA_SIZE /* bdinfo                        */
#ifdef CONFIG_USE_IRQ
	sub	r0, r0, #(CONFIG_STACKSIZE_IRQ+CONFIG_STACKSIZE_FIQ)
#endif
	sub	sp, r0, #12		/* leave 3 words for abort-stack    */
#endif
	ldr	sp, STACK_START

#ifndef CONFIG_ROM
clear_bss:
	ldr	r0, _bss_start		/* find start of bss segment        */
	add	r0, r0, #4		/* start at first byte of bss       */
	ldr	r1, _bss_end		/* stop here                        */
	mov 	r2, #0x00000000		/* clear                            */

clbss_l:str	r2, [r0]		/* clear loop...                    */
	add	r0, r0, #4
	cmp	r0, r1
	bne	clbss_l
#endif

#ifdef CONFIG_XDK3
	bl	cpu_id
#endif

	ldr	pc, _start_armboot

_start_armboot:
	.word TestEntry
#	.word _loop_forever
1:
	b	1b


/*
 *************************************************************************
 *
 * CPU_init_critical registers
 *
 * setup important registers
 * setup memory timing
 *
 *************************************************************************
 */


cpu_init_crit:
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002300	/* clear bits 13, 9:8 (--V- --RS) */
	bic	r0, r0, #0x00000087	/* clear bits 7, 2:0 (B--- -CAM) */
	orr	r0, r0, #0x00000002	/* set bit 2 (A) Align */
	orr	r0, r0, #0x00001000	/* set bit 12 (I) I-Cache */
	mcr	p15, 0, r0, c1, c0, 0

	/*
	 * Go setup Memory and board specific bits prior to relocation.
	 */
	mov	ip, lr		/* perserve link reg across call */
#	bl	platformsetup	/* go setup pll,mux,memory */
	bl	_loop_forever
	mov	lr, ip		/* restore link */
	mov	pc, lr		/* back to my caller */
/*
 *************************************************************************
 *
 * Interrupt handling
 *
 *************************************************************************
 */

@
@ IRQ stack frame.
@
#define S_FRAME_SIZE	72

#define S_OLD_R0	68
#define S_PSR		64
#define S_PC		60
#define S_LR		56
#define S_SP		52

#define S_IP		48
#define S_FP		44
#define S_R10		40
#define S_R9		36
#define S_R8		32
#define S_R7		28
#define S_R6		24
#define S_R5		20
#define S_R4		16
#define S_R3		12
#define S_R2		8
#define S_R1		4
#define S_R0		0

#define MODE_SVC 0x13
#define I_BIT	 0x80

/*
 * use bad_save_user_regs for abort/prefetch/undef/swi ...
 * use irq_save_user_regs / irq_restore_user_regs for IRQ/FIQ handling
 */

	.macro	bad_save_user_regs
	@ carve out a frame on current user stack
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}	@ Save user registers (now in svc mode) r0-r12

#	ldr	r2, _armboot_start
	ldr	r2, STACK_START
	sub	r2, r2, #(CONFIG_STACKSIZE+CFG_MALLOC_LEN)
	sub	r2, r2, #(CFG_GBL_DATA_SIZE+8)  @ set base 2 words into abort stack
	@ get values for "aborted" pc and cpsr (into parm regs)
	ldmia	r2, {r2 - r3}
	add	r0, sp, #S_FRAME_SIZE		@ grab pointer to old stack
	add	r5, sp, #S_SP
	mov	r1, lr
	stmia	r5, {r0 - r3}	@ save sp_SVC, lr_SVC, pc, cpsr
	mov	r0, sp		@ save current stack into r0 (param register)
	.endm

	.macro	irq_save_user_regs
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}^			@ Calling r0-r12
	@ !!!! R8 NEEDS to be saved !!!! a reserved stack spot would be good.
	add	r8, sp, #S_PC
	stmdb	r8, {sp, lr}^		@ Calling SP, LR
	str	lr, [r8, #0]		@ Save calling PC
	mrs	r6, spsr
	str	r6, [r8, #4]		@ Save CPSR
	str	r0, [r8, #8]		@ Save OLD_R0
	mov	r0, sp
	.endm

	.macro	irq_restore_user_regs
	ldmia	sp, {r0 - lr}^			@ Calling r0 - lr
	mov	r0, r0
	ldr	lr, [sp, #S_PC]			@ Get PC
	add	sp, sp, #S_FRAME_SIZE
	subs	pc, lr, #4		@ return & move spsr_svc into cpsr
	.endm

	.macro get_bad_stack
#	ldr	r13, _armboot_start		@ setup our mode stack
	ldr	r13, STACK_START
	sub	r13, r13, #(CONFIG_STACKSIZE+CFG_MALLOC_LEN)
	sub	r13, r13, #(CFG_GBL_DATA_SIZE+8) @ reserved a couple spots in abort stack

	str	lr, [r13]	@ save caller lr in position 0 of saved stack
	mrs	lr, spsr	@ get the spsr
	str	lr, [r13, #4]	@ save spsr in position 1 of saved stack
	mov	r13, #MODE_SVC	@ prepare SVC-Mode
	@ msr	spsr_c, r13
	msr	spsr, r13	@ switch modes, make sure moves will execute
	mov	lr, pc		@ capture return pc
	movs	pc, lr		@ jump to next instruction & switch modes.
	.endm

	.macro get_irq_stack			@ setup IRQ stack
	ldr	sp, IRQ_STACK_START
	.endm

	.macro get_fiq_stack			@ setup FIQ stack
	ldr	sp, FIQ_STACK_START
	.endm

/*
 * exception handlers
 */
	.align  5
undefined_instruction:
	get_bad_stack
	bad_save_user_regs
#	bl	do_undefined_instruction
1:
	b	1b

	.align	5
software_interrupt:
	movs pc, lr
#	get_bad_stack
#	bad_save_user_regs
#	bl	do_software_interrupt
1:
	b	1b

	.align	5
prefetch_abort:
	get_bad_stack
	bad_save_user_regs
#	bl	do_prefetch_abort
1:
	b	1b

	.align	5
data_abort:
	get_bad_stack
	bad_save_user_regs
#	bl	do_data_abort
1:
	b	1b

	.align	5
not_used:
	get_bad_stack
	bad_save_user_regs
#	bl	do_not_used
1:
	b	1b

#ifdef CONFIG_USE_IRQ

	.align	5
irq:
	get_irq_stack
	irq_save_user_regs
#	bl 	do_irq
#	bl	sysInterruptDispatch
	bl 	irq_dispatch
	irq_restore_user_regs		@return
1:
	b	1b

	.align	5
fiq:
	get_fiq_stack
	/* someone ought to write a more effiction fiq_save_user_regs */
	irq_save_user_regs
#	bl 	do_fiq
	bl 	fiq_dispatch
	irq_restore_user_regs
1:
	b	1b

#else

	.align	5
irq:
	get_bad_stack
	bad_save_user_regs
#	bl	do_irq
1:
	b	1b

	.align	5
fiq:
	get_bad_stack
	bad_save_user_regs
#	bl	do_fiq
1:
	b	1b

#endif

	.align	5
.globl reset_cpu
reset_cpu:
	ldr	r1, rstctl1	/* get clkm1 reset ctl */
	mov	r3, #0x0
	strh	r3, [r1]	/* clear it */
	mov	r3, #0x8
	strh	r3, [r1]	/* force dsp+arm reset */

.globl test_fail
_loop_forever:
test_fail:
	b	_loop_forever

/*
 *      dma_flush_range(start, end)
 *
 *      Clean and invalidate the specified virtual address range.
 *
 *      - start - virtual start address
 *      - end   - virtual end address
 */
#define CACHE_DLINESIZE 32
.globl arm926_dma_flush_range
arm926_dma_flush_range:
        bic     r0, r0, #CACHE_DLINESIZE - 1
1:
#ifndef CONFIG_CPU_DCACHE_WRITETHROUGH
        mcr     p15, 0, r0, c7, c14, 1          @ clean+invalidate D entry
#else
        mcr     p15, 0, r0, c7, c10, 1          @ clean D entry
#endif
        add     r0, r0, #CACHE_DLINESIZE
        cmp     r0, r1
        blo     1b
        mcr     p15, 0, r0, c7, c10, 4          @ drain WB
        mov     pc, lr



rstctl1:
	.word	0xfffece10

#ifdef CONFIG_XDK3
scu_info:
	.word	0x5100f000

cpu_id:
        ldr     r0, scu_info
        mrc	p15,0,r1,c0,c0,0
        str     r1, [r0, #8]

	mov	pc, lr
#endif

