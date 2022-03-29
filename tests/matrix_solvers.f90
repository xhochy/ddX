!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file tests/ddlpb_esolv_iterations.f90
!! Test for different solvers parameters
!! NOTE: This test is not a definitive test. If the values are different
!!       maybe the new ones are correct as they might be improved values.
!!       But, the default values should be used as a benchmark
!!
!! @version 1.0.0
!! @author Abhinav Jha
!! @date 2022-03-29

program main
use ddx_core
use ddx_operators
use ddx_solvers
use ddx
use ddx_lpb
implicit none

character(len=255) :: fname
type(ddx_type) :: ddx_data
integer :: info

real(dp) :: esolv_one, esolv_two, tol
integer :: i, istatus, iprint, default_value

real(dp), allocatable :: computed_epsilon(:), computed_eta(:), &
                       & computed_kappa(:), computed_lmax(:)
real(dp), external :: dnrm2

! Read input file name
call getarg(1, fname)
write(*, *) "Using provided file ", trim(fname), " as a config file"
call ddfromfile(fname, ddx_data, tol, iprint, info)
if(info .ne. 0) stop "info != 0"

! Initial values
default_value = zero
esolv_one = zero
esolv_two = zero

! Computation for different storage
write(*,*) 'Different storage of matrix'
default_value = 1
call solve(ddx_data, default_value, &
           & ddx_data % params % itersolver, esolv_one)
write(*,*) 'Esolv : ', esolv_one
default_value = 0
call solve(ddx_data, default_value, &
           & ddx_data % params % itersolver, esolv_two)
write(*,*) 'Esolv : ', esolv_two

if(abs(esolv_one - esolv_two) .gt. 1e-8) then
  write(*,*) 'Different solvation energies for storing and not storing the matrix'
  stop 1
endif

default_value = zero
esolv_one = zero
esolv_two = zero

! Computation for different solvers
write(*,*) 'Different Solvers'
default_value = 1
call solve(ddx_data, ddx_data % params % matvecmem, &
           & default_value, esolv_one)
write(*,*) 'Esolv : ', esolv_one
default_value = 2
call solve(ddx_data, ddx_data % params % matvecmem, &
           & default_value, esolv_two)
write(*,*) 'Esolv : ', esolv_two

if(abs(esolv_one - esolv_two) .gt. 1e-8) then
  write(*,*) 'Different solvation energies for different solvers'
  stop 1
endif


call ddfree(ddx_data)

contains

subroutine solve(ddx_data, matvecmem, iterative_solver, esolv)
    type(ddx_type), intent(inout) :: ddx_data
    real(dp), intent(inout) :: esolv
    integer, intent(in) :: matvecmem
    integer, intent(in) :: iterative_solver

    type(ddx_type) :: ddx_data2
    real(dp), allocatable :: phi_cav2(:)
    real(dp), allocatable :: gradphi_cav2(:,:)
    real(dp), allocatable :: hessianphi_cav2(:,:,:)
    real(dp), allocatable :: psi2(:,:)
    real(dp), allocatable :: force2(:,:)

    call ddinit(ddx_data % params % nsph, ddx_data % params % charge, &
        & ddx_data % params % csph(1, :), &
        & ddx_data % params % csph(2, :), ddx_data % params % csph(3, :), ddx_data % params % rsph, &
        & ddx_data % params % model, ddx_data % params % lmax, ddx_data % params % ngrid, 0, &
        & ddx_data % params % fmm, ddx_data % params % pm, ddx_data % params % pl, &
        & ddx_data % params % se, &
        & ddx_data % params % eta, ddx_data % params % eps, ddx_data % params % kappa, matvecmem,&
        & iterative_solver, ddx_data % params % maxiter, &
        & ddx_data % params % jacobi_ndiis, ddx_data % params % gmresr_j, &
        & ddx_data % params % gmresr_dim, ddx_data % params % nproc, ddx_data2, info)

    allocate(phi_cav2(ddx_data2 % constants % ncav), &
            & gradphi_cav2(3, ddx_data2 % constants % ncav), &
            & hessianphi_cav2(3, 3, ddx_data2 % constants % ncav), &
            & psi2(ddx_data2 % constants % nbasis, ddx_data2 % params % nsph), &
            & force2(3, ddx_data2 % params % nsph))


    write(*,*) 'Store sparse matrices : ', ddx_data2 % params % matvecmem
    write(*,*) 'Iterative Solver      : ', ddx_data2 % params % itersolver

    gradphi_cav2 = zero; phi_cav2 = zero
    hessianphi_cav2 = zero; psi2 = zero; force2 = zero

    call mkrhs(ddx_data2 % params, ddx_data2 % constants, ddx_data2 % workspace, &
            &  1, phi_cav2, 1, gradphi_cav2, 1, hessianphi_cav2, psi2)

    call ddsolve(ddx_data2, phi_cav2, gradphi_cav2, hessianphi_cav2, psi2, tol, esolv, force2, info)
    deallocate(phi_cav2, gradphi_cav2, hessianphi_cav2, psi2, force2)
    call ddfree(ddx_data2)
    return
end subroutine solve

end program main

