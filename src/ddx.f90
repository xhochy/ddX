!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file src/ddx.f90
!! Main driver routine of the ddX with all the per-model solvers
!!
!! @version 1.0.0
!! @author Aleksandr Mikhalev
!! @date 2021-02-25

module ddx
use ddx_core
use ddx_operators
use ddx_solvers
use ddx_cosmo
use ddx_pcm
implicit none

contains

!> Main solver routine
!!
!! Solves the problem within COSMO model using a domain decomposition approach.
!!
!! @param[in] ddx_data: ddX object with all input information
!! @param[in] phi_cav: Potential at cavity points
!! @param[in] gradphi_cav: Gradient of a potential at cavity points
!! @param[in] psi: TODO
!! @param[out] esolv: Solvation energy
!! @param[out] force: Analytical forces
subroutine ddsolve(ddx_data, phi_cav, gradphi_cav, psi, esolv, force, info)
    ! Inputs
    type(ddx_type), intent(inout)  :: ddx_data
    real(dp), intent(in) :: phi_cav(ddx_data % constants % ncav), &
        & gradphi_cav(3, ddx_data % constants % ncav), psi(ddx_data % constants % nbasis, ddx_data % params % nsph)
    ! Outputs
    real(dp), intent(out) :: esolv, force(3, ddx_data % params % nsph)
    integer, intent(out) :: info
    ! Find proper model
    select case(ddx_data % params % model)
        ! COSMO model
        case (1)
            call ddcosmo(ddx_data, phi_cav, gradphi_cav, psi, esolv, force, info)
        ! PCM model
        case (2)
            call ddpcm(ddx_data, phi_cav, gradphi_cav, psi, esolv, force, info)
        ! LPB model
        case (3)
            stop "LPB model is not yet fully supported"
        ! Error case
        case default
            stop "Non-supported model"
    end select
end subroutine ddsolve

subroutine ddsolve_energy(ddx_data, phi_cav, psi, esolv, info)
    ! Inputs
    type(ddx_type), intent(inout)  :: ddx_data
    real(dp), intent(in) :: phi_cav(ddx_data % constants % ncav), &
        & psi(ddx_data % constants % nbasis, ddx_data % params % nsph)
    ! Outputs
    real(dp), intent(out) :: esolv
    integer, intent(out) :: info
    ! Find proper model
    select case(ddx_data % params % model)
        ! COSMO model
        case (1)
            ddx_data % xs = zero
            call ddcosmo_energy(ddx_data % params, ddx_data % constants, &
                & ddx_data % workspace, phi_cav, psi, ddx_data % xs, esolv, &
                & ddx_data % phi_grid, ddx_data % phi, info)
        ! PCM model
        case (2)
            ddx_data % xs = zero
            call ddpcm_energy(ddx_data % params, ddx_data % constants, &
                & ddx_data % workspace, phi_cav, psi, ddx_data % xs, esolv, &
                & ddx_data % phi_grid, ddx_data % phi, ddx_data % phiinf, &
                & ddx_data % phieps, info)
        ! LPB model
        case (3)
            stop "LPB model is not yet fully supported"
        ! Error case
        case default
            stop "Non-supported model"
    end select
end subroutine ddsolve_energy

subroutine ddsolve_adjoint(ddx_data, phi_cav, psi, esolv, info)
    ! Inputs
    type(ddx_type), intent(inout)  :: ddx_data
    real(dp), intent(in) :: phi_cav(ddx_data % constants % ncav), &
        & psi(ddx_data % constants % nbasis, ddx_data % params % nsph)
    ! Outputs
    real(dp), intent(out) :: esolv
    integer, intent(out) :: info
    ! Find proper model
    select case(ddx_data % params % model)
        ! COSMO model
        case (1)
            ddx_data % xs = zero
            call ddcosmo_energy(ddx_data % params, ddx_data % constants, &
                & ddx_data % workspace, phi_cav, psi, ddx_data % xs, esolv, &
                & ddx_data % phi_grid, ddx_data % phi, info)
        ! PCM model
        case (2)
            ddx_data % xs = zero
            call ddpcm_energy(ddx_data % params, ddx_data % constants, &
                & ddx_data % workspace, phi_cav, psi, ddx_data % xs, esolv, &
                & ddx_data % phi_grid, ddx_data % phi, ddx_data % phiinf, &
                & ddx_data % phieps, info)
        ! LPB model
        case (3)
            stop "LPB model is not yet fully supported"
        ! Error case
        case default
            stop "Non-supported model"
    end select
end subroutine ddsolve_adjoint

end module ddx
