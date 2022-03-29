!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file tests/ddlpb_esolv_iterations.f90
!! Test for solvation energy and number of outer iterations for different
!! values of input parameter
!! NOTE: This test is not a definitive test. If the values are different
!!       maybe the new ones are correct as they might be improved values.
!!       But, the default values should be used as a benchmark
!!
!! @version 1.0.0
!! @author Abhinav Jha
!! @date 2022-03-28

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

real(dp) :: esolv, default_value, tol
integer :: i, istatus, iprint, default_lmax_val
real(dp), allocatable :: default_epsilon(:), default_eta(:), &
                       & default_kappa(:), default_lmax(:)

real(dp), allocatable :: computed_epsilon(:), computed_eta(:), &
                       & computed_kappa(:), computed_lmax(:)
real(dp), external :: dnrm2

! Read input file name
call getarg(1, fname)
write(*, *) "Using provided file ", trim(fname), " as a config file"
call ddfromfile(fname, ddx_data, tol, iprint, info)
if(info .ne. 0) stop "info != 0"

! Allocation for variable vectors
! default_"variable_name" : These are the precomputed values
! computed_"variable_name" : These are the computed values
allocate(default_epsilon(4), default_eta(4), &
       & default_kappa(4), default_lmax(4), &
       & computed_epsilon(4), computed_eta(4), &
       & computed_kappa(4), computed_lmax(4), stat= istatus)

if (istatus.ne.0) write(6,*) 'Allocation failed'

!Default values precomputed
!epsilon_solv : 2, 20, 200, 2000
default_epsilon = (/ -5.3518110117345332E-004, -9.7393853923451006E-004, &
                   & -1.0237954253809903E-003, -1.0288501533655906E-003 /)
!eta : 0.0001, 0.001, 0.01, 0.1
default_eta = (/ -1.0144763156304426E-003, -1.0144763156304426E-003, &
               & -1.0144761325115853E-003, -1.0151060052969220E-003 /)
!kappa : 0.5, 0.25, 0.16667, 0.125
default_kappa = (/ -1.0228739915625511E-003, -1.0192321310712657E-003,&
                 & -1.0171251065945882E-003, -1.0158211256043079E-003 /)
!lmax : 2, 4, 8, 16
default_lmax = (/ -9.9977268971430206E-004, -1.0128441259120659E-003, &
                & -1.0157913843224611E-003, -1.0177420746553952E-003 /)

! Initial values
computed_epsilon = zero
computed_eta = zero
computed_kappa = zero
computed_lmax = zero
! Computation for different eps_solv
write(*,*) 'Varying values of epsilon_solv'
do i = 1, 4
  default_value = 0.2*(10**i)
  write(*,*) 'epsilon_solv : ', default_value
  call solve(ddx_data, computed_epsilon(i), default_value, &
           & ddx_data % params % eta, ddx_data % params % kappa, &
           & ddx_data % params % lmax)
  write(*,*) 'Esolv : ', computed_epsilon(i)
end do

call check_values(default_epsilon, computed_epsilon)

! Computation for different eta
write(*,*) 'Varying values of eta'
do i = 1, 4
  default_value = 0.00001*(10**i)
  write(*,*) 'eta : ', default_value
  call solve(ddx_data, computed_eta(i), ddx_data % params % eps, &
           & default_value, ddx_data % params % kappa, ddx_data % params % lmax)
  write(*,*) 'Esolv : ', computed_eta(i)
end do

call check_values(default_eta, computed_eta)

! Computation for different kappa
write(*,*) 'Varying values of kappa'
do i = 1, 4
  default_value = 1.0/(2.0*i)
  write(*,*) 'kappa : ', default_value
  call solve(ddx_data, computed_kappa(i), ddx_data % params % eps, &
           & ddx_data % params % eta, default_value, ddx_data % params % lmax)
  write(*,*) 'Esolv : ', computed_kappa(i)
end do

call check_values(default_kappa, computed_kappa)

! Computation for different lmax
write(*,*) 'Varying values of lmax'
do i = 1, 4
  default_lmax_val = 2**i
  write(*,*) 'lmax : ', default_lmax_val
  call solve(ddx_data, computed_lmax(i), ddx_data % params % eps, &
           & ddx_data % params % eta, ddx_data % params % kappa, default_lmax_val)
  write(*,*) 'Esolv : ', computed_lmax(i)
end do

call check_values(default_lmax, computed_lmax)

deallocate(default_epsilon, default_eta, &
       & default_kappa, default_lmax, &
       & computed_epsilon, computed_eta, &
       & computed_kappa, computed_lmax, stat = istatus)

if (istatus.ne.0) write(6,*) 'Deallocation failed'

call ddfree(ddx_data)

contains

subroutine solve(ddx_data, esolv_in, epsilon_solv, eta, kappa, lmax)
    type(ddx_type), intent(inout) :: ddx_data
    real(dp), intent(inout) :: esolv_in
    real(dp), intent(in) :: epsilon_solv
    real(dp), intent(in) :: eta
    real(dp), intent(in) :: kappa
    integer, intent(in) :: lmax

    type(ddx_type) :: ddx_data2
    real(dp), allocatable :: phi_cav2(:)
    real(dp), allocatable :: gradphi_cav2(:,:)
    real(dp), allocatable :: hessianphi_cav2(:,:,:)
    real(dp), allocatable :: psi2(:,:)
    real(dp), allocatable :: force2(:,:)

    call ddinit(ddx_data % params % nsph, ddx_data % params % charge, &
        & ddx_data % params % csph(1, :), &
        & ddx_data % params % csph(2, :), ddx_data % params % csph(3, :), ddx_data % params % rsph, &
        & ddx_data % params % model, lmax, ddx_data % params % ngrid, 0, &
        & ddx_data % params % fmm, ddx_data % params % pm, ddx_data % params % pl, &
        & ddx_data % params % se, &
        & eta, epsilon_solv, kappa, 0,&
        & ddx_data % params % itersolver, ddx_data % params % maxiter, &
        & ddx_data % params % jacobi_ndiis, ddx_data % params % gmresr_j, &
        & ddx_data % params % gmresr_dim, ddx_data % params % nproc, ddx_data2, info)

    allocate(phi_cav2(ddx_data2 % constants % ncav), gradphi_cav2(3, ddx_data2 % constants % ncav), &
            & hessianphi_cav2(3, 3, ddx_data2 % constants % ncav), &
            & psi2(ddx_data2 % constants % nbasis, ddx_data2 % params % nsph), &
            & force2(3, ddx_data2 % params % nsph))

    gradphi_cav2 = zero; phi_cav2 = zero
    hessianphi_cav2 = zero; psi2 = zero; force2 = zero

    call mkrhs(ddx_data2 % params, ddx_data2 % constants, ddx_data2 % workspace, &
            &  1, phi_cav2, 1, gradphi_cav2, 1, hessianphi_cav2, psi2)

    call ddsolve(ddx_data2, phi_cav2, gradphi_cav2, hessianphi_cav2, psi2, tol, esolv_in, force2, info)
    deallocate(phi_cav2, gradphi_cav2, hessianphi_cav2, psi2, force2)
    call ddfree(ddx_data2)
    return
end subroutine solve

! This subroutine checks if the default and computed values are same
subroutine check_values(default_value, computed_value)
    real(dp), intent(in) :: default_value(4)
    real(dp), intent(in) :: computed_value(4)
    integer :: i = 1

    do i = 1, 4
      if(abs(default_value(i) - computed_value(i)) .gt. 1d-9) then
        write(*,*) 'Issue in value ', i,' default : ', default_value(i), ', computed : ',&
                  & computed_value(i)
        stop 1
      endif
    end do
end subroutine check_values

end program main

