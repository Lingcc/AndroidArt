/*
 * ===========================================================================
 *  Common subroutines and data
 * ===========================================================================
 */

    .text
    .align  2

/*
 * We've detected a condition that will result in an exception, but the exception
 * has not yet been thrown.  Just bail out to the reference interpreter to deal with it.
 * TUNING: for consistency, we may want to just go ahead and handle these here.
 */
#define MTERP_LOGGING 0
common_errDivideByZero:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpLogDivideByZeroException
#endif
    jmp     MterpCommonFallback

common_errArrayIndex:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpLogArrayIndexException
#endif
    jmp     MterpCommonFallback

common_errNegativeArraySize:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpLogNegativeArraySizeException
#endif
    jmp     MterpCommonFallback

common_errNoSuchMethod:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpLogNoSuchMethodException
#endif
    jmp     MterpCommonFallback

common_errNullObject:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpLogNullObjectException
#endif
    jmp     MterpCommonFallback

common_exceptionThrown:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG0(%esp)
    call    MterpLogExceptionThrownException
#endif
    jmp     MterpCommonFallback

MterpSuspendFallback:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG0(%esp)
    movl    THREAD_FLAGS_OFFSET(%eax), %eax
    movl    %eax, OUT_ARG2(%esp)
    call    MterpLogSuspendFallback
#endif
    jmp     MterpCommonFallback

/*
 * If we're here, something is out of the ordinary.  If there is a pending
 * exception, handle it.  Otherwise, roll back and retry with the reference
 * interpreter.
 */
MterpPossibleException:
    movl    rSELF, %eax
    testl   $$-1, THREAD_EXCEPTION_OFFSET(%eax)
    jz      MterpFallback
    /* intentional fallthrough - handle pending exception. */

/*
 * On return from a runtime helper routine, we've found a pending exception.
 * Can we handle it here - or need to bail out to caller?
 *
 */
MterpException:
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpHandleException
    testl   %eax, %eax
    jz      MterpExceptionReturn
    REFRESH_IBASE
    movl    OFF_FP_CODE_ITEM(rFP), %eax
    movl    OFF_FP_DEX_PC(rFP), %ecx
    lea     CODEITEM_INSNS_OFFSET(%eax), rPC
    lea     (rPC, %ecx, 2), rPC
    movl    rPC, OFF_FP_DEX_PC_PTR(rFP)
    /* resume execution at catch block */
    FETCH_INST
    GOTO_NEXT
    /* NOTE: no fallthrough */

/*
 * Check for suspend check request.  Assumes rINST already loaded, rPC advanced and
 * still needs to get the opcode and branch to it, and flags are in lr.
 */
MterpCheckSuspendAndContinue:
    movl    rSELF, %eax
    EXPORT_PC
    testl   $$(THREAD_SUSPEND_REQUEST | THREAD_CHECKPOINT_REQUEST), THREAD_FLAGS_OFFSET(%eax)
    jz      1f
    movl    %eax, OUT_ARG0(%esp)
    call    MterpSuspendCheck
    REFRESH_IBASE
1:
    GOTO_NEXT

/*
 * Bail out to reference interpreter.
 */
MterpFallback:
    EXPORT_PC
#if MTERP_LOGGING
    movl    rSELF, %eax
    movl    %eax, OUT_ARG0(%esp)
    lea     OFF_FP_SHADOWFRAME(rFP), %ecx
    movl    %ecx, OUT_ARG1(%esp)
    call    MterpLogFallback
#endif
MterpCommonFallback:
    xor     %eax, %eax
    jmp     MterpDone

/*
 * On entry:
 *  uint32_t* rFP  (should still be live, pointer to base of vregs)
 */
MterpExceptionReturn:
    movl    $$1, %eax
    jmp     MterpDone
MterpReturn:
    movl    OFF_FP_RESULT_REGISTER(rFP), %edx
    movl    %eax, (%edx)
    movl    %ecx, 4(%edx)
    movl    rSELF, %eax
    testl   $$(THREAD_SUSPEND_REQUEST | THREAD_CHECKPOINT_REQUEST), THREAD_FLAGS_OFFSET(%eax)
    jz      1f
    movl    %eax, OUT_ARG0(%esp)
    call    MterpSuspendCheck
1:
    mov     $$1, %eax
MterpDone:
    /* Restore callee save register */
    movl    EBP_SPILL(%esp), %ebp
    movl    EDI_SPILL(%esp), %edi
    movl    ESI_SPILL(%esp), %esi
    movl    EBX_SPILL(%esp), %ebx

    /* pop up frame */
    addl    $$FRAME_SIZE, %esp
    .cfi_adjust_cfa_offset -FRAME_SIZE
    ret

    .cfi_endproc
    .size   ExecuteMterpImpl, .-ExecuteMterpImpl