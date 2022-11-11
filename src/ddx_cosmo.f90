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
implicit none

contains

!> ddCOSMO solver
!!
!! Solves the problem within COSMO model using a domain decomposition approach.
!!
!! @param[in] ddx_data: ddX object with all input information
!! @param[in] phi_cav: Potential at cavity points
!! @param[in] gradphi_cav: Gradient of a potential at cavity points
!! @param[in] psi: TODO
!! @param[in] tol
!! @param[out] esolv: Solvation energy
!! @param[out] force: Analytical forces
!! @param[out] info
subroutine ddcosmo(params, constants, workspace, state, phi_cav, gradphi_cav, &
        & psi, tol, esolv, force, info)
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: phi_cav(constants % ncav), &
        & gradphi_cav(3, constants % ncav), &
        & psi(constants % nbasis, params % nsph), tol
    real(dp), intent(out) :: esolv, force(3, params % nsph)
    integer, intent(out) :: info
    real(dp), external :: ddot

    call ddcosmo_ddpcm_rhs(params, constants, state)
    call ddcosmo_guess(params, constants, state)
    call ddcosmo_solve(params, constants, workspace, state, tol)

    ! Solvation energy is computed
    esolv = pt5*ddot(constants % n, state % xs, 1, psi, 1)

    ! Get forces if needed
    if (params % force .eq. 1) then
        call ddcosmo_adjoint(params, constants, workspace, state, psi, tol)
        call ddcosmo_forces(params, constants, workspace, state, phi_cav, &
            & gradphi_cav, psi, force)
    end if
end subroutine ddcosmo

subroutine ddcosmo_guess(params, constants, state)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_state_type), intent(inout) :: state

    ! TODO: improve the guess
    state % s = zero
    state % xs = zero
end subroutine ddcosmo_guess

subroutine ddcosmo_solve(params, constants, workspace, state, tol)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: tol

    state % xs_niter =  params % maxiter
    call ddcosmo_solve_worker(params, constants, workspace, phi_cav, &
        & state % xs, state % xs_niter, state % xs_rel_diff, state % xs_time, &
        & tol, state % phi_grid, state % phi)
end subroutine ddcosmo_solve

subroutine ddcosmo_adjoint(params, constants, workspace, state, psi, tol)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph)
    real(dp), intent(in) :: tol

    state % s_niter = params % maxiter
    call ddcosmo_adjoint_worker(params, constants, workspace, psi, tol, &
        & state % s, state % s_niter, state % s_rel_diff, state % s_time)
end subroutine ddcosmo_adjoint

subroutine ddcosmo_forces(params, constants, workspace, state, phi_cav, &
    & gradphi_cav, psi, force)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: phi_cav(constants % ncav)
    real(dp), intent(in) :: gradphi_cav(3, constants % ncav)
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph)
    real(dp), intent(out) :: force(3, params % nsph)

    call ddcosmo_forces_worker(params, constants, workspace, &
        & state % phi_grid, gradphi_cav, psi, state % s, state % sgrid, &
        & state % xs, state % zeta, force)
end subroutine ddcosmo_forces

subroutine ddcosmo_geom_forces(params, constants, workspace, state, phi_cav, &
    & gradphi_cav, psi, force)
    implicit none
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    type(ddx_workspace_type), intent(inout) :: workspace
    type(ddx_state_type), intent(inout) :: state
    real(dp), intent(in) :: phi_cav(constants % ncav)
    real(dp), intent(in) :: gradphi_cav(3, constants % ncav)
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph)
    real(dp), intent(out) :: force(3, params % nsph)

    call ddcosmo_geom_forces_worker(params, constants, workspace, &
        & state % phi_grid, gradphi_cav, psi, state % s, state % sgrid, &
        & state % xs, state % zeta, force)
end subroutine ddcosmo_geom_forces

!> Solve primal ddCOSMO system to find solvation energy
!!
!! @param[in] params
!! @param[in] constants
!! @param[inout] workspace
!! @param[in] phi_cav
!! @param[in] psi
!! @param[in] xs_mode: behaviour of the input `xs`. If it is 0 then input value of
!!      `xs` is ignored and initialized with zero. If it is 1 then input value `xs`
!!      is used as an initial guess for the solver.
!! @param[inout] xs
!! @param[in] tol
!! @param[out] esolv
!! @param[out] phi_grid
!! @param[out] phi
subroutine ddcosmo_solve_worker(params, constants, workspace, phi_cav, &
        & xs, xs_niter, xs_rel_diff, xs_time, tol, phi_grid, &
        & phi)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    real(dp), intent(in) :: phi_cav(constants % ncav), tol
    !! Input+output
    real(dp), intent(inout) :: xs(constants % nbasis, params % nsph)
    integer, intent(inout) :: xs_niter
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(out) :: xs_rel_diff(xs_niter), xs_time
    real(dp), intent(out) :: phi_grid(params % ngrid, params % nsph)
    real(dp), intent(out) :: phi(constants % nbasis, params % nsph)
    !! Local variables
    character(len=255) :: string
    real(dp) :: start_time, finish_time, r_norm
    !! The code
    ! Solve ddCOSMO system L X = -Phi with a given initial guess
    start_time = omp_get_wtime()
    call jacobi_diis(params, constants, workspace, tol, &
        & workspace % tmp_rhs, xs, xs_niter, xs_rel_diff, lx, &
        & ldm1x, hnorm)
    finish_time = omp_get_wtime()
    xs_time = finish_time - start_time
    ! Check if solver did not converge
    if (params % error_flag .ne. 0) return
    ! Clear status
end subroutine ddcosmo_solve_worker

!> Solve adjoint ddCOSMO system
!!
!! @param[in] params
!! @param[in] constants
!! @param[inout] workspace
!! @param[in] psi
!! @param[in] tol
!! @param[inout] s
subroutine ddcosmo_adjoint_worker(params, constants, workspace, psi, tol, s, &
        & s_niter, s_rel_diff, s_time)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph), tol
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(inout) :: s(constants % nbasis, params % nsph), s_time
    integer, intent(inout) :: s_niter
    real(dp), intent(out) :: s_rel_diff(s_niter)
    !! Local variables
    real(dp) :: start_time, finish_time, r_norm
    character(len=255) :: string
    real(dp), external :: ddot
    !! The code
    call cpu_time(start_time)
    call jacobi_diis(params, constants, workspace, tol, psi, s, s_niter, &
        & s_rel_diff, lstarx, ldm1x, hnorm)
    call cpu_time(finish_time)
    s_time = finish_time - start_time
    ! Check if solver did not converge
    if (workspace % error_flag .ne. 0) return 
end subroutine ddcosmo_adjoint_worker

subroutine ddcosmo_forces_worker(params, constants, workspace, phi_grid, &
        & gradphi_cav, psi, s, sgrid, xs, zeta, force)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    real(dp), intent(in) :: phi_grid(params % ngrid, params % nsph), &
        & gradphi_cav(3, constants % ncav), &
        & psi(constants % nbasis, params % nsph), &
        & s(constants % nbasis, params % nsph), &
        & xs(constants % nbasis, params % nsph)
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(out) :: sgrid(params % ngrid, params % nsph), &
        & zeta(constants % ncav), &
        & force(3, params % nsph)
    !! Local variables
    integer :: isph, icav, igrid, inode, jnode, jsph, jnear
    real(dp) :: tmp1, tmp2, d(3), dnorm
    real(dp), external :: ddot, dnrm2
    character(len=255) :: string
    !! The code
    ! Get values of S on grid
    call ddeval_grid_work(constants % nbasis, params % ngrid, params % nsph, &
        & constants % vgrid, constants % vgrid_nbasis, one, s, zero, sgrid)
    force = zero
    do isph = 1, params % nsph
        call contract_grad_L(params, constants, isph, xs, sgrid, &
            & workspace % tmp_vylm(:, 1), workspace % tmp_vdylm(:, :, 1), &
            & workspace % tmp_vplm(:, 1), &
            & workspace % tmp_vcos(:, 1), &
            & workspace % tmp_vsin(:, 1), force(:, isph))
        call contract_grad_U(params, constants, isph, sgrid, phi_grid, &
            & force(:, isph))
    end do
    force = - pt5 * force

    icav = 0
    do isph = 1, params % nsph
        do igrid = 1, params % ngrid
            if (constants % ui(igrid, isph) .ne. zero) then
                icav = icav + 1
                zeta(icav) = constants % wgrid(igrid) * &
                    & constants % ui(igrid, isph) * ddot(constants % nbasis, &
                    & constants % vgrid(1, igrid), 1, &
                    & s(1, isph), 1)
                force(:, isph) = force(:, isph) &
                    & - pt5*zeta(icav)*gradphi_cav(:, icav)
            end if
        end do
    end do

    !! Last term where we compute gradients of potential at centers of atoms
    !! spawned by intermediate zeta.
    if(params % fmm .eq. 1) then
        !! This step can be substituted by a proper dgemm if zeta
        !! intermediate is converted from cavity points to all grid points
        !! with zero values at internal grid points
        ! P2M step
        icav = 0
        do isph = 1, params % nsph
            inode = constants % snode(isph)
            workspace % tmp_node_m(:, inode) = zero
            do igrid = 1, params % ngrid
                if(constants % ui(igrid, isph) .eq. zero) cycle
                icav = icav + 1
                call fmm_p2m(constants % cgrid(:, igrid), zeta(icav), &
                    & one, params % pm, constants % vscales, one, &
                    & workspace % tmp_node_m(:, inode))
            end do
            workspace % tmp_node_m(:, inode) = workspace % tmp_node_m(:, inode) / &
                & params % rsph(isph)
        end do
        ! M2M, M2L and L2L translations
        call tree_m2m_rotation(params, constants, workspace % tmp_node_m)
        call tree_m2l_rotation(params, constants, workspace % tmp_node_m, &
            & workspace % tmp_node_l)
        call tree_l2l_rotation(params, constants, workspace % tmp_node_l)
        ! Now compute near-field FMM gradients
        ! Cycle over all spheres
        icav = 0
        workspace % tmp_efld = zero
        do isph = 1, params % nsph
            ! Cycle over all external grid points
            do igrid = 1, params % ngrid
                if (constants % ui(igrid, isph) .eq. zero) cycle
                icav = icav + 1
                ! Cycle over all near-field admissible pairs of spheres,
                ! including pair (isph, isph) which is a self-interaction
                inode = constants % snode(isph)
                do jnear = constants % snear(inode), constants % snear(inode+1)-1
                    ! Near-field interactions are possible only between leaf
                    ! nodes, which must contain only a single input sphere
                    jnode = constants % near(jnear)
                    jsph = constants % order(constants % cluster(1, jnode))
                    d = params % csph(:, isph) + &
                        & constants % cgrid(:, igrid)*params % rsph(isph) - &
                        & params % csph(:, jsph)
                    dnorm = dnrm2(3, d, 1)
                    workspace % tmp_efld(:, jsph) = workspace % tmp_efld(:, jsph) + &
                        & zeta(icav)*d/(dnorm**3)
                end do
            end do
        end do
        ! Take into account far-field FMM gradients only if pl > 0
        if (params % pl .gt. 0) then
            tmp1 = one / sqrt(3d0) / constants % vscales(1)
            do isph = 1, params % nsph
                inode = constants % snode(isph)
                tmp2 = tmp1 / params % rsph(isph)
                workspace % tmp_efld(3, isph) = workspace % tmp_efld(3, isph) + &
                    & tmp2*workspace % tmp_node_l(3, inode)
                workspace % tmp_efld(1, isph) = workspace % tmp_efld(1, isph) + &
                    & tmp2*workspace % tmp_node_l(4, inode)
                workspace % tmp_efld(2, isph) = workspace % tmp_efld(2, isph) + &
                    & tmp2*workspace % tmp_node_l(2, inode)
            end do
        end if
        do isph = 1, params % nsph
            force(:, isph) = force(:, isph) &
                & -pt5*workspace % tmp_efld(:, isph)*params % charge(isph)
        end do
    ! Naive quadratically scaling implementation
    else
        ! This routines actually computes -grad, not grad
        call efld(constants % ncav, zeta, constants % ccav, &
            & params % nsph, params % csph, workspace % tmp_efld)
        do isph = 1, params % nsph
            force(:, isph) = force(:, isph) &
                & + pt5*workspace % tmp_efld(:, isph)*params % charge(isph)
        end do
    end if
end subroutine ddcosmo_forces_worker

subroutine ddcosmo_geom_forces_worker(params, constants, workspace, phi_grid, &
        & gradphi_cav, psi, s, sgrid, xs, zeta, force)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    real(dp), intent(in) :: phi_grid(params % ngrid, params % nsph), &
        & gradphi_cav(3, constants % ncav), &
        & psi(constants % nbasis, params % nsph), &
        & s(constants % nbasis, params % nsph), &
        & xs(constants % nbasis, params % nsph)
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(out) :: sgrid(params % ngrid, params % nsph), &
        & zeta(constants % ncav), &
        & force(3, params % nsph)
    !! Local variables
    integer :: isph, icav, igrid, inode, jnode, jsph, jnear
    real(dp) :: tmp1, tmp2, d(3), dnorm
    real(dp), external :: ddot, dnrm2
    character(len=255) :: string
    !! The code
    ! Get values of S on grid
    call ddeval_grid_work(constants % nbasis, params % ngrid, params % nsph, &
        & constants % vgrid, constants % vgrid_nbasis, one, s, zero, sgrid)
    force = zero
    do isph = 1, params % nsph
        call contract_grad_L(params, constants, isph, xs, sgrid, &
            & workspace % tmp_vylm(:, 1), workspace % tmp_vdylm(:, :, 1), &
            & workspace % tmp_vplm(:, 1), &
            & workspace % tmp_vcos(:, 1), &
            & workspace % tmp_vsin(:, 1), force(:, isph))
        call contract_grad_U(params, constants, isph, sgrid, phi_grid, &
            & force(:, isph))
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
                zeta(icav) = constants % wgrid(igrid) * &
                    & constants % ui(igrid, isph) * ddot(constants % nbasis, &
                    & constants % vgrid(1, igrid), 1, &
                    & s(1, isph), 1)
            end if
        end do
    end do

end subroutine ddcosmo_geom_forces_worker

end module ddx_cosmo

