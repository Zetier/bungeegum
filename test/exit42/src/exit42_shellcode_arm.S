.syntax unified
.arm

.global _start
.type _start, %function

_start:
	mov r0, #42
	mov r7, #1
	svc #0
