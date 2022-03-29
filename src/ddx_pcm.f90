!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file src/ddx_pcm.f90
!! PCM solver
!!
!! @version 1.0.0
!! @author Aleksandr Mikhalev
!! @date 2021-02-25

!> High-level subroutines for ddpcm
module ddx_pcm
use ddx_core
use ddx_operators
use ddx_solvers
implicit none

contains

!> ddPCM solver
!!
!! Solves the problem within PCM model using a domain decomposition approach.
!!
!! @param[in] ddx_data: ddX object with all input information
!! @param[in] phi_cav: Potential at cavity points
!! @param[in] gradphi_cav: Gradient of a potential at cavity points
!! @param[in] psi: TODO
!! @param[out] esolv: Solvation energy
!! @param[out] force: Analytical forces
!! @param[out] info
subroutine ddpcm(ddx_data, phi_cav, gradphi_cav, psi, tol, esolv, force, info)
    !! Inputs
    type(ddx_type), intent(inout) :: ddx_data
    real(dp), intent(in) :: phi_cav(ddx_data % constants % ncav), &
        & gradphi_cav(3, ddx_data % constants % ncav), &
        & psi(ddx_data % constants % nbasis, ddx_data % params % nsph), tol
    !! Outputs
    real(dp), intent(out) :: esolv, force(3, ddx_data % params % nsph)
    integer, intent(out) :: info
    !! Local variables
    integer :: xs_mode, phieps_mode, s_mode, y_mode
    ! Local variables
    ! Zero initial guess on X (solution of the ddCOSMO system)
    xs_mode = 0
    ! Use Phi that will be computed by the `ddpcm_energy` as the initial guess
    phieps_mode = 1
    ! Get the energy
    ddx_data % xs_niter = ddx_data % params % maxiter
    ddx_data % phieps_niter = ddx_data % params % maxiter
    call ddpcm_energy(ddx_data % params, ddx_data % constants, &
        & ddx_data % workspace, phi_cav, psi, xs_mode, ddx_data % xs, &
        & ddx_data % xs_niter, ddx_data % xs_rel_diff, ddx_data % xs_time, &
        & tol, esolv, &
        & ddx_data % phi_grid, ddx_data % phi, ddx_data % phiinf, &
        & phieps_mode, ddx_data % phieps, ddx_data % phieps_niter, &
        & ddx_data % phieps_rel_diff, ddx_data % phieps_time, info)
    ! Get forces if needed
    if (ddx_data % params % force .eq. 1) then
        ! Zero initial guesses for adjoint systems
        s_mode = 0
        y_mode = 0
        ! Solve adjoint systems
        ddx_data % s_niter = ddx_data % params % maxiter
        ddx_data % y_niter = ddx_data % params % maxiter
        call ddpcm_adjoint(ddx_data % params, ddx_data % constants, &
            & ddx_data % workspace, psi, tol, s_mode, ddx_data % s, &
            & ddx_data % s_niter, ddx_data % s_rel_diff, ddx_data % s_time, &
            & y_mode, &
            & ddx_data % y, ddx_data % y_niter, ddx_data % y_rel_diff, &
            & ddx_data % y_time, info)
        ! Get forces, they are initialized with zeros in gradr
        call ddpcm_forces(ddx_data % params, ddx_data % constants, &
            & ddx_data % workspace, ddx_data % phi_grid, gradphi_cav, &
            & psi, ddx_data % phi, ddx_data % phieps, ddx_data % s, &
            & ddx_data % sgrid, ddx_data % y, ddx_data % ygrid, ddx_data % g, &
            & ddx_data % q, ddx_data % qgrid, ddx_data % xs, ddx_data % zeta, &
            & force, info)
    end if
end subroutine ddpcm

!> Solve primal ddPCM system to find solvation energy
!!
!! @param[in] params
!! @param[in] constants
!! @param[inout] workspace
!! @param[in] phi_cav
!! @param[in] psi
!! @param[in] xs_mode
!! @param[inout] xs
!! @param[out] esolv
!! @param[in] info
subroutine ddpcm_energy(params, constants, workspace, phi_cav, psi, xs_mode, &
        & xs, xs_niter, xs_rel_diff, xs_time, tol, esolv, phi_grid, phi, &
        & phiinf, phieps_mode, phieps, phieps_niter, phieps_rel_diff, &
        & phieps_time, info)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    integer, intent(in) :: xs_mode, phieps_mode
    real(dp), intent(in) :: phi_cav(constants % ncav), &
        & psi(constants % nbasis, params % nsph), tol
    !! Input+output
    real(dp), intent(inout) :: xs(constants % nbasis, params % nsph), &
        & phieps(constants % nbasis, params % nsph)
    integer, intent(inout) :: xs_niter, phieps_niter
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(out) :: esolv, phi_grid(params % ngrid, params % nsph), &
        & phi(constants % nbasis, params % nsph), &
        & phiinf(constants % nbasis, params % nsph), &
        & xs_rel_diff(xs_niter), phieps_rel_diff(phieps_niter), xs_time, &
        & phieps_time
    integer, intent(out) :: info
    !! Local variables
    real(dp) :: start_time, finish_time, r_norm
    character(len=255) :: string
    real(dp), external :: ddot
    !! The code
    ! At first check if parameters, constants and workspace are correctly
    ! initialized
    if (params % error_flag .ne. 0) then
        string = "ddpcm_energy: `params` is in error state"
        call params % print_func(string)
        info = 1
        return
    end if
    if (constants % error_flag .ne. 0) then
        string = "ddpcm_energy: `constants` is in error state"
        call params % print_func(string)
        info = 1
        return
    end if
    if (workspace % error_flag .ne. 0) then
        string = "ddpcm_energy: `workspace` is in error state"
        call params % print_func(string)
        info = 1
        return
    end if
    ! Unwrap sparsely stored potential at cavity points phi_cav into phi_grid
    ! and multiply it by characteristic function at cavity points ui
    call ddcav_to_grid_work(params % ngrid, params % nsph, constants % ncav, &
        & constants % icav_ia, constants % icav_ja, phi_cav, phi_grid)
    workspace % tmp_cav = phi_cav * constants % ui_cav
    call ddcav_to_grid_work(params % ngrid, params % nsph, constants % ncav, &
        & constants % icav_ia, constants % icav_ja, workspace % tmp_cav, &
        & workspace % tmp_grid)
    ! Integrate against spherical harmonics and Lebedev weights to get Phi
    call ddintegrate_sph_work(constants % nbasis, params % ngrid, &
        & params % nsph, constants % vwgrid, constants % vgrid_nbasis, &
        & one, workspace % tmp_grid, zero, phi)
    ! Compute Phi_infty
    ! force dx called from rinfx to add the diagonal
    call rinfx(params, constants, workspace, phi, phiinf)
    ! Select initial guess for the ddPCM system
    select case (phieps_mode)
        ! Zero guess
        case (0)
            phieps = zero
        ! Phi as the initial guess
        case (1)
            phieps = phi
        ! Otherwise use user-provided value as the initial guess
    end select
    ! Solve ddPCM system R_eps Phi_epsilon = Phi_infty
    call cpu_time(start_time)
    if (params % itersolver .eq. 1) then 
        call jacobi_diis(params, constants, workspace, tol, phiinf, phieps, &
            & phieps_niter, phieps_rel_diff, repsx, apply_repsx_prec, hnorm, info)
    else
        call gmresr(params, constants, workspace, tol, phiinf, phieps, phieps_niter, &
            & r_norm, repsx, info)
    end if
    call cpu_time(finish_time)
    phieps_time = finish_time - start_time
    ! Check if solver did not converge
    if (info .ne. 0) then
        string = "ddpcm_energy: solver for ddPCM system did not converge"
        call params % print_func(string)
        return
    end if
    ! Zero initialize guess for the solution of the ddCOSMO system if needed
    if (xs_mode .eq. 0) then
        xs = zero
    end if
    ! Set right hand side to -Phi_epsilon
    workspace % tmp_rhs = -phieps
    ! Solve ddCOSMO system L X = -Phi_epsilon with a proper initial guess
    info = params % maxiter
    call cpu_time(start_time)
    if (params % itersolver .eq. 1) then
        call jacobi_diis(params, constants, workspace, tol, workspace % tmp_rhs, &
            & xs, xs_niter, xs_rel_diff, lx, ldm1x, hnorm, info)
    else
        call gmresr(params, constants, workspace, tol, workspace % tmp_rhs, &
            & xs, xs_niter, r_norm, lx, info)
    end if
    call cpu_time(finish_time)
    xs_time = finish_time - start_time
    ! Check if solver did not converge
    if (info .ne. 0) then
        string = "ddpcm_energy: solver for ddCOSMO system did not converge"
        call params % print_func(string)
        return
    end if
    ! Solvation energy is computed
    esolv = pt5*ddot(constants % n, xs, 1, psi, 1)
    ! Clear status
    info = 0
end subroutine ddpcm_energy

subroutine ddpcm_adjoint(params, constants, workspace, psi, tol, s_mode, s, &
        & s_niter, s_rel_diff, s_time, y_mode, y, y_niter, y_rel_diff, &
        & y_time, info)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    integer, intent(in) :: s_mode, y_mode
    real(dp), intent(in) :: psi(constants % nbasis, params % nsph), tol
    !! Input+output
    real(dp), intent(inout) :: s(constants % nbasis, params % nsph), &
        & y(constants % nbasis, params % nsph)
    integer, intent(inout) :: s_niter, y_niter
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(out) :: s_rel_diff(s_niter), y_rel_diff(y_niter), &
        & s_time, y_time
    integer, intent(out) :: info
    !! Local variables
    real(dp) :: start_time, finish_time, r_norm
    character(len=255) :: string
    !! The code
    ! Zero initialize `s` if needed
    if (s_mode .eq. 0) then
        s = zero
    end if
    ! Solve the adjoint ddCOSMO system
    call cpu_time(start_time)
    if (params % itersolver .eq. 1) then 
        call jacobi_diis(params, constants, workspace, tol, psi, s, s_niter, &
            & s_rel_diff, lstarx, ldm1x, hnorm, info)
    else
        call gmresr(params, constants, workspace, tol, psi, s, s_niter, &
            & r_norm, lstarx, info)
    end if
    call cpu_time(finish_time)
    s_time = finish_time - start_time
    ! Check if solver did not converge
    if (info .ne. 0) then
        string = "ddpcm_energy: solver for adjoint ddCOSMO system did not " &
            & // "converge"
        call params % print_func(string)
        return
    end if
    ! Zero initialize `y` if needed
    if (y_mode .eq. 0) then
        y = zero
    end if
    ! Solve adjoint ddPCM system
    call cpu_time(start_time)
    if (params % itersolver .eq. 1) then 
        call jacobi_diis(params, constants, workspace, tol, s, y, y_niter, &
            & y_rel_diff, rstarepsx, apply_rstarepsx_prec, hnorm, info)
    else
        call gmresr(params, constants, workspace, tol, s, y, y_niter, &
            & r_norm, rstarepsx, info)
    end if
    call cpu_time(finish_time)
    y_time = finish_time - start_time
    ! Check if solver did not converge
    if (info .ne. 0) then
        string = "ddpcm_energy: solver for adjoint ddPCM system did not " &
            & // "converge"
        call params % print_func(string)
        return
    end if
    ! Clear status
    info = 0
end subroutine ddpcm_adjoint

subroutine ddpcm_forces(params, constants, workspace, phi_grid, gradphi_cav, &
        & psi, phi, phieps, s, sgrid, y, ygrid, g, q, qgrid, xs, zeta, force, info)
    !! Inputs
    type(ddx_params_type), intent(in) :: params
    type(ddx_constants_type), intent(in) :: constants
    real(dp), intent(in) :: phi_grid(params % ngrid, params % nsph), &
        & gradphi_cav(3, constants % ncav), &
        & psi(constants % nbasis, params % nsph), &
        & phi(constants % nbasis, params % nsph), &
        & phieps(constants % nbasis, params % nsph), &
        & s(constants % nbasis, params % nsph), &
        & y(constants % nbasis, params % nsph), &
        & xs(constants % nbasis, params % nsph)
    !! Temporary buffers
    type(ddx_workspace_type), intent(inout) :: workspace
    !! Outputs
    real(dp), intent(out) :: sgrid(params % ngrid, params % nsph), &
        & ygrid(params % ngrid, params % nsph), &
        & g(constants % nbasis, params % nsph), &
        & q(constants % nbasis, params % nsph), &
        & qgrid(params % ngrid, params % nsph), &
        & zeta(constants % ncav), &
        & force(3, params % nsph)
    integer, intent(out) :: info
    !! Local variables
    integer :: isph, icav, igrid, inode, jnode, jsph, jnear
    real(dp) :: tmp1, tmp2, d(3), dnorm
    real(dp), external :: ddot, dnrm2
    !! The code
    ! Get grid values of S and Y
    call dgemm('T', 'N', params % ngrid, params % nsph, &
        & constants % nbasis, one, constants % vgrid, constants % vgrid_nbasis, &
        & s, constants % nbasis, zero, sgrid, params % ngrid)
    call dgemm('T', 'N', params % ngrid, params % nsph, &
        & constants % nbasis, one, constants % vgrid, constants % vgrid_nbasis, &
        & y, constants % nbasis, zero, ygrid, params % ngrid)
    g = phieps - phi
    q = s - fourpi/(params % eps-one)*y
    qgrid = sgrid - fourpi/(params % eps-one)*ygrid
    ! gradr initializes forces with zeros
    call gradr(params, constants, workspace, g, ygrid, force)
    do isph = 1, params % nsph
        call fdoka(params, constants, isph, xs, sgrid(:, isph), &
            & workspace % tmp_vylm(:, 1), workspace % tmp_vdylm(:, :, 1), &
            & workspace % tmp_vplm(:, 1), workspace % tmp_vcos(:, 1), &
            & workspace % tmp_vsin(:, 1), force(:, isph)) 
        call fdokb(params, constants, isph, xs, sgrid, &
            & workspace % tmp_vylm(:, 1), workspace % tmp_vdylm(:, :, 1), &
            & workspace % tmp_vplm(:, 1), workspace % tmp_vcos(:, 1), &
            & workspace % tmp_vsin(:, 1), force(:, isph))
        call fdoga(params, constants, isph, qgrid, phi_grid, force(:, isph)) 
    end do
    force = -pt5 * force
    icav = 0
    do isph = 1, params % nsph
        do igrid = 1, params % ngrid
            if(constants % ui(igrid, isph) .ne. zero) then
                icav = icav + 1
                zeta(icav) = -pt5 * constants % wgrid(igrid) * &
                    & constants % ui(igrid, isph) * ddot(constants % nbasis, &
                    & constants % vgrid(1, igrid), 1, q(1, isph), 1)
                force(:, isph) = force(:, isph) + &
                    & zeta(icav)*gradphi_cav(:, icav)
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
                if(constants % ui(igrid, isph) .eq. zero) cycle
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
            force(:, isph) = force(:, isph) + &
                & workspace % tmp_efld(:, isph)*params % charge(isph)
        end do
    ! Naive quadratically scaling implementation
    else
        ! This routines actually computes -grad, not grad
        call efld(constants % ncav, zeta, constants % ccav, params % nsph, &
            & params % csph, workspace % tmp_efld)
        do isph = 1, params % nsph
            force(:, isph) = force(:, isph) - &
                & workspace % tmp_efld(:, isph)*params % charge(isph)
        end do
    end if
    ! Clear status
    info = 0
end subroutine ddpcm_forces

end module ddx_pcm