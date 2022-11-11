!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file src/ddx_cosmo.f90
!! COSMO solver
!!
!! @version 1.0.0
!! @author Aleksandr Mikhalev
!! @date 2021-02-25

!> High-level subroutines for ddcosmo
module ddx_cosmo
! Get ddx-operators
use ddx_operators
use ddx_multipolar_solutes
implicit none

contains

!> ddCOSMO solver
!!
!! Solves the problem within COSMO model using a domain decomposition approach.
!!
!! @param[in] params: User specified parameters
!! @param[in] constants: Precomputed constants
!! @param[inout] workspace: Preallocated workspaces
!! @param[inout] state: ddx state (contains solutions and RHSs)
!! @param[in] phi_cav: Potential at cavity points, size (ncav)
!! @param[in] gradphi_cav: Gradient of a potential at cavity points, required
!!     by the forces, size (3, ncav)
!! @param[in] psi: Representation of the solute potential in spherical
!!     harmonics, size (nbasis, nsph)
!! @param[in] tol: Tolerance for the linear system solver
!! @param[out] esolv: Solvation energy
!! @param[out] force: Analytical forces
!!
subroutine ddcosmo(params, constants, workspace, state, phi_cav, gradphi_cav, &
        & psi, tol, esolv, force)
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: phi_cav(constants % ncav), &
        & gradphi_cav(3, constants % ncav), &
        & psi(constants % nbasis, params % nsph), tol
    real(dp), intent(out) :: esolv, force(3, params % nsph)
    real(dp), external :: ddot

    call ddcosmo_ddpcm_rhs(params, constants, workspace, state, phi_cav)
    call ddcosmo_guess(params, constants, workspace, state)
    call ddcosmo_solve(params, constants, workspace, state, tol)
    ! check if ddcosmo_solve is in error
    if (workspace % error_flag .eq. 1) return

    ! Solvation energy is computed
    esolv = pt5*ddot(constants % n, state % xs, 1, psi, 1)

    ! Get forces if needed
    if (params % force .eq. 1) then
        ! solve the adjoint
        call ddcosmo_guess_adjoint(params, constants, workspace, state, psi)
        call ddcosmo_solve_adjoint(params, constants, workspace, state, &
            & psi, tol)
        if (workspace % error_flag .eq. 1) return

        ! evaluate the analytical derivatives
        force = zero
        call ddcosmo_solvation_force_terms(params, constants, workspace, state, &
            & phi_cav, gradphi_cav, psi, force)
    end if
end subroutine ddcosmo

!> Do a guess for the primal ddCOSMO linear system
!!
!! @param[in] params: User specified parameters
!! @param[in] constants: Precomputed constants
!! @param[inout] workspace: Preallocated workspaces
!! @param[inout] state: ddx state (contains solutions and RHSs)
!!
subroutine ddcosmo_guess(params, constants, workspace, state)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state

    ! apply the diagonal preconditioner as a guess
    call ldm1x(params, constants, workspace, state % phi, state % xs)
end subroutine ddcosmo_guess

!> Do a guess for the adjoint ddCOSMO linear system
!!
!! @param[in] params: User specified parameters
!! @param[in] constants: Precomputed constants
!! @param[inout] workspace: Preallocated workspaces
!! @param[inout] state: ddx state (contains solutions and RHSs)
!! @param[in] psi: Representation of the solute potential in spherical
!!     harmonics, size (nbasis, nsph)
!!
subroutine ddcosmo_guess_adjoint(params, constants, workspace, state, psi)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph)

    ! apply the diagonal preconditioner as a guess
    call ldm1x(params, constants, workspace, psi, state % s)
end subroutine ddcosmo_guess_adjoint

!> Solve the primal ddCOSMO linear system
!!
!! @param[in] params: User specified parameters
!! @param[in] constants: Precomputed constants
!! @param[inout] workspace: Preallocated workspaces
!! @param[inout] state: ddx state (contains solutions and RHSs)
!! @param[in] tol: Tolerance for the linear system solver
!!
subroutine ddcosmo_solve(params, constants, workspace, state, tol)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: tol
    ! local variables
    real(dp) :: start_time, finish_time

    state % xs_niter =  params % maxiter
    start_time = omp_get_wtime()
    call jacobi_diis(params, constants, workspace, tol, state % phi, &
        & state % xs, state % xs_niter, state % xs_rel_diff, lx, ldm1x, &
        & hnorm)
    if (workspace % error_flag .eq. 1) return
    finish_time = omp_get_wtime()
    state % xs_time = finish_time - start_time

end subroutine ddcosmo_solve

!> Solve the adjoint ddCOSMO linear system
!!
!! @param[in] params: User specified parameters
!! @param[in] constants: Precomputed constants
!! @param[inout] workspace: Preallocated workspaces
!! @param[inout] state: ddx state (contains solutions and RHSs)
!! @param[in] psi: Representation of the solute potential in spherical
!!     harmonics, size (nbasis, nsph)
!! @param[in] tol: Tolerance for the linear system solver
!!
subroutine ddcosmo_solve_adjoint(params, constants, workspace, state, &
        & psi, tol)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph)
    real(dp), intent(in) :: tol
    ! local variables
    real(dp) :: start_time, finish_time

    state % s_niter = params % maxiter
    start_time = omp_get_wtime()
    call jacobi_diis(params, constants, workspace, tol, psi, state % s, &
        & state % s_niter, state % s_rel_diff, lstarx, ldm1x, hnorm)
    finish_time = omp_get_wtime()
    state % s_time = finish_time - start_time

end subroutine ddcosmo_solve_adjoint

!> Compute the solvation term of the forces (solute aspecific). This must
!> be summed to the solute specific term to get the full forces.
!!
!! @param[in] params: User specified parameters
!! @param[in] constants: Precomputed constants
!! @param[inout] workspace: Preallocated workspaces
!! @param[inout] state: ddx state (contains solutions and RHSs)
!! @param[in] phi_cav: electric potential at the cavity points, size (ncav)
!! @param[in] gradphi_cav: electric field at the cavity points, size (3, ncav)
!! @param[in] psi: representation of the solute density, size (nbasis, nsph)
!! @param[inout] force: force term
!!
subroutine ddcosmo_solvation_force_terms(params, constants, workspace, &
        & state, phi_cav, gradphi_cav, psi, force)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: phi_cav(constants % ncav)
    real(dp), intent(in) :: gradphi_cav(3, constants % ncav)
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph)
    real(dp), intent(inout) :: force(3, params % nsph)
    ! local variables
    real(dp), external :: ddot
    integer :: icav, isph, igrid

    ! Get values of S on the grid
    call ddeval_grid_work(constants % nbasis, params % ngrid, params % nsph, &
        & constants % vgrid, constants % vgrid_nbasis, one, state % s, zero, &
        & state % sgrid)
    ! Get the values of phi on the grid
    call ddcav_to_grid_work(params % ngrid, params % nsph, constants % ncav, &
        & constants % icav_ia, constants % icav_ja, phi_cav, state % phi_grid)

    force = zero
    do isph = 1, params % nsph
        call contract_grad_l(params, constants, isph, state % xs, &
            & state % sgrid, workspace % tmp_vylm(:, 1), &
            & workspace % tmp_vdylm(:, :, 1), workspace % tmp_vplm(:, 1), &
            & workspace % tmp_vcos(:, 1), workspace % tmp_vsin(:, 1), &
            & force(:, isph))
        call contract_grad_u(params, constants, isph, state % sgrid, &
            & state % phi_grid, force(:, isph))
    end do
    force = - pt5 * force

    ! assemble the intermediate zeta: S weighted by U evaluated on the
    ! exposed grid points. This is not required here, but it is used
    ! in later steps.
    icav = 0
    do isph = 1, params % nsph
        do igrid = 1, params % ngrid
            if (constants % ui(igrid, isph) .ne. zero) then
                icav = icav + 1
                state % zeta(icav) = constants % wgrid(igrid) * &
                    & constants % ui(igrid, isph) * ddot(constants % nbasis, &
                    & constants % vgrid(1, igrid), 1, state % s(1, isph), 1)
            end if
        end do
    end do

end subroutine ddcosmo_solvation_force_terms

end module ddx_cosmo

