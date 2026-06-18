	.text
	.globl branch_phi_twouse
	.type branch_phi_twouse, @function
branch_phi_twouse:
	movl	%edx, %ecx
	cmp	%esi, %edi
	jb	.Lmerge
	movl	%esi, %ecx
.Lmerge:
	leal	1(%rcx), %eax
	addl	%ecx, %eax
	ret
	.size branch_phi_twouse, .-branch_phi_twouse
	.section .note.GNU-stack,"",@progbits
