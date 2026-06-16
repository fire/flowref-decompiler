	.text
	.globl branch_phi_add
	.type branch_phi_add, @function
branch_phi_add:
	movl	%edx, %ecx
	cmp	%esi, %edi
	jb	.Lmerge
	movl	%esi, %ecx
.Lmerge:
	leal	1(%rcx), %eax
	ret
	.size branch_phi_add, .-branch_phi_add
	.section .note.GNU-stack,"",@progbits
