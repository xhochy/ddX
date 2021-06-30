!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file src/ddx_parameters.f90
!! The type ddx_params_type is defined here along with its routines meant to
!! init, deinit and read it from a file in certain fromats. All the new code to
!! read user input from different file formats shall be added here.
!!
!! @version 1.0.0
!! @author Aleksandr Mikhalev
!! @date 2021-06-15

!> Module to treat properly user input parameters
module ddx_parameters

! Include compile-time definitions
use ddx_definitions

! Disable implicit types
implicit none

interface
    subroutine print_func_interface(string)
        character(len=255), intent(in) :: string
    end subroutine
end interface

!> Type to check and store user input parameters
type ddx_params_type
    !> Model to use 1 for COSMO, 2 for PCM, 3 for LPB.
    integer :: model
    !> Whether computing analytical forces will be required (1) or not (0).
    integer :: force
    !> Relative dielectric permittivity.
    real(dp) :: eps
    !> Debye-H\"{u}ckel parameter. Referenced only in LPB model (model=3)
    real(dp) :: kappa
    !> Regularization parameter.
    real(dp) :: eta
    !> Shift of the regularization. -1 for interior, 0 for centered and
    !!      1 for outer regularization.
    real(dp) :: se
    !> Maximal degree of modeling spherical harmonics.
    integer :: lmax
    !> Number of Lebedev grid points on each sphere.
    integer :: ngrid
    !> Iterative solver to be used. 1 for Jacobi/DIIS.
    !!
    !! Other solvers might be added later.
    integer :: itersolver
    !> Relative threshold for the iterative solvers.
    real(dp) :: tol
    !> Maximum number of iterations for the iterative solver.
    integer :: maxiter
    !> Number of extrapolation points for Jacobi/DIIS solver. Referenced only
    !!      if Jacobi solver is used.
    integer :: ndiis
    !> Enable (1) or disable (0) use of FMM techniques.
    integer :: fmm
    !> Maximal degree of spherical harmonics for a multipole expansion.
    !!
    !! If this value is -1 then no far-field FMM interactions are performed.
    integer :: pm
    !> Maximal degree of spherical harmonics for a local expansion.
    !!
    !! If this value is -1 then no far-field FMM interactions are performed.
    integer :: pl
    !> Number of OpenMP threads to be used. Currently, only nproc=1 is
    !!      supported as the ddX is sequential right now.
    integer :: nproc
    !> Number of atoms in the molecule.
    integer :: nsph
    !> Charges of atoms of a dimension (nsph).
    real(dp), allocatable :: charge(:)
    !> Centers of atoms of a dimension (3, nsph).
    real(dp), allocatable :: csph(:, :)
    !> Array of radii of atoms of a dimension (nsph).
    real(dp), allocatable :: rsph(:)
    !> Error state. 0 in case of no error or 1 if there were errors or if the
    !! object is not initialised.
    integer :: error_flag = 1
    !> Last error message
    character(len=255) :: error_message
    !> Error printing function
    procedure(print_func_interface), pointer, nopass :: print_func
end type ddx_params_type

contains

!> Initialize and check input parameters
!!
!! @param[in] model: Choose model: 1 for COSMO, 2 for PCM and 3 for LPB.
!! @param[in] force: 1 if forces will probably be required and 0 otherwise.
!! @param[in] eps: Relative dielectric permittivity. eps > 1.
!! @param[in] kappa: Debye-H\"{u}ckel parameter.
!! @param[in] eta: Regularization parameter. 0 < eta <= 1.
!! @param[in] se: Shift of the regularization. -1 for interior, 0 for
!!      centered and 1 for outer regularization.
!! @param[in] lmax: Maximal degree of modeling spherical harmonics.
!!      `lmax` >= 0.
!! @param[in] ngrid: Number of Lebedev grid points `ngrid` >= 0.
!! @param[in] itersolver: Iterative solver to be used. 1 for Jacobi iterative
!!      solver. Other solvers might be added later.
!! @param[in] tol: Relative error threshold for an iterative solver. tol must
!!      in range [1d-14, 1].
!! @param[in] maxiter: Maximum number of iterations for an iterative solver.
!!      maxiter > 0.
!! @param[in] ndiis: Number of extrapolation points for Jacobi/DIIS solver.
!!      ndiis >= 1.
!! @param[in] fmm: 1 to use FMM acceleration and 0 otherwise.
!! @param[in] pm: Maximal degree of multipole spherical harmonics. Ignored in
!!      the case `fmm=0`. Value -1 means no far-field FMM interactions are
!!      computed. `pm` >= -1.
!! @param[in] pl: Maximal degree of local spherical harmonics. Ignored in
!!      the case `fmm=0`. Value -1 means no far-field FMM interactions are
!!      computed. `pl` >= -1.
!! @param[in] nproc: Number of OpenMP threads to be used where applicable.
!!      nproc >= 0. If input nproc=0 then a default number of threads,
!!      controlled by the environment variable `OMP_NUM_THREADS` during
!!      runtime, will be used. If OpenMP support in ddX is
!!      disabled, only possible input values are 0 or 1 and both inputs lead
!!      to the same output nproc=1 since the library is not parallel.
!! @param[in] nsph: Number of atoms. nsph > 0.
!! @param[in] charge: Charges of atoms. Dimension is `(nsph)`.
!! @param[in] csph: Coordinates of atoms. Dimension is `(3, nsph)`.
!! @param[in] rsph: Van-der-Waals radii of atoms. Dimension is `(nsph)`.
!! @param[in] print_func: Function to print errors.
!! @param[out] params: Object containing all inputs.
!! @param[out] info: flag of succesfull exit
!!      = 0: Succesfull exit
!!      = -1: One of the arguments had an illegal value, check
!!          params % error_message
!!      = 1: Allocation of memory to copy geometry data failed.
subroutine params_init(model, force, eps, kappa, eta, se, lmax, ngrid, &
        & itersolver, tol, maxiter, ndiis, fmm, pm, pl, nproc, nsph, charge, &
        & csph, rsph, print_func, params, info)
    !! Inputs
    ! Model to use 1 for COSMO, 2 for PCM, 3 for LPB.
    integer, intent(in) :: model
    ! Whether computing analytical forces will be required (1) or not (0).
    integer, intent(in) :: force
    ! Relative dielectric permittivity.
    real(dp), intent(in) :: eps
    ! Debye-H\"{u}ckel parameter. Referenced only in LPB model (model=3)
    real(dp), intent(in) :: kappa
    ! Regularization parameter.
    real(dp), intent(in) :: eta
    ! Shift of the regularization. -1 for interior, 0 for centered and
    !      1 for outer regularization.
    real(dp), intent(in) :: se
    ! Maximal degree of modeling spherical harmonics.
    integer, intent(in) :: lmax
    ! Number of Lebedev grid points on each sphere.
    integer, intent(in) :: ngrid
    ! Iterative solver to be used. 1 for Jacobi/DIIS.
    !
    ! Other solvers might be added later.
    integer, intent(in) :: itersolver
    ! Relative threshold for the iterative solvers.
    real(dp), intent(in) :: tol
    ! Maximum number of iterations for the iterative solver.
    integer, intent(in) :: maxiter
    ! Number of extrapolation points for Jacobi/DIIS solver. Referenced only
    !      if Jacobi solver is used.
    integer, intent(in) :: ndiis
    ! Enable (1) or disable (0) use of FMM techniques.
    integer, intent(in) :: fmm
    ! Maximal degree of spherical harmonics for a multipole expansion.
    !
    ! If this value is -1 then no far-field FMM interactions are performed.
    integer, intent(in) :: pm
    ! Maximal degree of spherical harmonics for a local expansion.
    !
    ! If this value is -1 then no far-field FMM interactions are performed.
    integer, intent(in) :: pl
    ! Number of OpenMP threads to be used. Currently, only nproc=1 is
    !      supported as the ddX is sequential right now.
    integer, intent(in) :: nproc
    ! Number of atoms in the molecule.
    integer, intent(in) :: nsph
    ! Charges of atoms of a dimension (nsph).
    real(dp), intent(in) :: charge(nsph)
    ! Centers of atoms of a dimension (3, nsph).
    real(dp), intent(in) :: csph(3, nsph)
    ! Array of radii of atoms of a dimension (nsph).
    real(dp), intent(in) :: rsph(nsph)
    ! Error printing function
    procedure(print_func_interface) :: print_func
    !! Outputs
    type(ddx_params_type), intent(out) :: params
    integer, intent(out) :: info
    !! Local variables
    integer :: igrid, i
    !! The code
    ! Model, 1=COSMO, 2=PCM, 3=LPB
    if ((model .lt. 1) .or. (model .gt. 3)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `model`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % model = model
    ! Check if forces are needed
    if ((force .lt. 0) .or. (force .gt. 1)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `force`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % force = force
    ! Relative dielectric permittivity
    if (eps .le. one) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `eps`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % eps = eps
    ! Debye-H\"{u}ckel parameter (only used in ddLPB)
    if ((model .eq. 3) .and. (kappa .lt. zero)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `kappa`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % kappa = kappa
    ! Regularization parameter
    if ((eta .le. zero) .or. (eta .gt. one)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `eta`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % eta = eta
    ! Shift of a regularization
    if ((se .lt. -one) .or. (se .gt. one)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `se`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % se = se
    ! Degree of modeling spherical harmonics
    if (lmax .lt. 0) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `lmax`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % lmax = lmax
    ! Check number of Lebedev grid points
    igrid = 0
    do i = 1, nllg
        if (ng0(i) .eq. ngrid) then
            igrid = i
            exit
        end if
    end do
    if (igrid .eq. 0) then
        params % error_flag = 1
        params % error_message = "params_init: Unsupported value of `ngrid`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % ngrid = ngrid
    ! Iterative solver: 1=Jacobi
    if (itersolver .ne. 1) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `itersolver`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % itersolver = itersolver
    ! Relative threshold for an iterative solver
    if ((tol .lt. 1d-14) .or. (tol .gt. one)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `tol`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % tol = tol
    ! Maximum number of iterations
    if (maxiter .le. 0) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `maxiter`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % maxiter = maxiter
    ! Number of DIIS extrapolation points (ndiis=25 works)
    if (ndiis .lt. 0) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `ndiis`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % ndiis = ndiis
    ! Check if FMM-acceleration is needed
    if ((fmm .lt. 0) .or. (fmm .gt. 1)) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `fmm`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % fmm = fmm
    ! Set FMM parameters if FMM is needed
    if (fmm .eq. 1) then
        ! Maximal degree of multipole spherical harmonics. Value -1 means no 
        ! far-field interactions are to be computed, only near-field
        ! interactions are taken into account.
        if (pm .lt. -1) then
            params % error_flag = 1
            params % error_message = "params_init: invalid value of `pm`"
            call print_func(params % error_message)
            info = -1
            return
        end if
        ! Maximal degree of local spherical harmonics. Value -1 means no 
        ! far-field interactions are to be computed, only near-field
        ! interactions are taken into account.
        if (pl .lt. -1) then
            params % error_flag = 1
            params % error_message = "params_init: invalid value of `pl`"
            call print_func(params % error_message)
            info = -1
            return
        end if
        ! If far-field interactions are to be ignored
        if ((pl .eq. -1) .or. (pm .eq. -1)) then
            params % pm = -1
            params % pl = -1
        ! If far-field interactions are to be taken into account
        else
            params % pm = pm
            params % pl = pl
        end if
    else
        ! These values are ignored if fmm flag is 0
        params % pm = -2
        params % pl = -2
    end if
    ! Number of OpenMP threads to be used
    ! As of now only sequential version with nproc=1 is supported, providing
    ! nproc=0 means it is up to ddX to decide on parallelism which is not yet
    ! available.
    if (nproc .ne. 1 .and. nproc .ne. 0) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `nproc`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    ! Only 1 thread is used (due to disabled OpenMP)
    params % nproc = 1
    ! Number of atoms
    if (nsph .le. 0) then
        params % error_flag = 1
        params % error_message = "params_init: invalid value of `nsph`"
        call print_func(params % error_message)
        info = -1
        return
    end if
    params % nsph = nsph
    ! Allocation of charge, csph and rsph
    allocate(params % charge(nsph), params % csph(3, nsph), &
        & params % rsph(nsph), stat=info)
    if (info .ne. 0) then
        params % error_flag = 1
        params % error_message = "params_init: `charge`, `csph` and `rsph` " &
            & // "allocations failed"
        call print_func(params % error_message)
        info = 1
        return
    end if
    params % charge = charge
    params % csph = csph
    params % rsph = rsph
    ! Set print function for errors
    params % print_func => print_func
    ! Clear error state
    params % error_flag = 0
    params % error_message = ""
end subroutine params_init

!> Print header with parameters
subroutine params_print(params)
    !! Input
    type(ddx_params_type), intent(in) :: params
    !! Local variables
    character(len=255) :: string
    !! The code
    if (params % error_flag .ne. 0) then
        call params % print_func("Parameters are not initialised or in " // &
            & "error state")
    else
        write(string, "(A)") "DDX parameters object"
        call params % print_func(string)
        write(string, "(A,A)") "Model: ", trim(model_str(params % model))
        call params % print_func(string)
        write(string, "(A,L1)") "Forces: ", params % force .eq. 1
        call params % print_func(string)
        write(string, "(A,ES23.16E3)") "Eps: ", params % eps
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
        call params % print_func(string)
    end if
end subroutine params_print

!> Free memory used by parameters
!! @param[inout] params: Object containing all inputs
!! @param[out] info: flag of succesfull exit
!!      = 0: Succesfull exit
!!      = -1: params is in error state
!!      = 1: Deallocation of memory failed.
subroutine params_deinit(params, info)
    !! Input
    type(ddx_params_type), intent(inout) :: params
    !! Output
    integer, intent(out) :: info
    !! Code
    ! Check if input params is in proper state
    if (params % error_flag .eq. 1) then
        params % error_flag = 1
        params % error_message = "params_deinit: `params` is in error state"
        info = -1
        return
    end if
    ! Deallocate memory to avoid leaks
    deallocate(params % charge, stat=info)
    if (info .ne. 0) then
        params % error_flag = 1
        params % error_message = "params_deinit: `charge` deallocation failed"
        info = 1
    end if
    deallocate(params % csph, stat=info)
    if (info .ne. 0) then
        params % error_flag = 1
        params % error_message = "params_deinit: `csph` deallocation failed"
        info = 1
    end if
    deallocate(params % rsph, stat=info)
    if (info .ne. 0) then
        params % error_flag = 1
        params % error_message = "params_deinit: `rsph` deallocation failed"
        info = 1
    end if
    info = 0
    ! Set params in error state to avoid its usage (due to deallocation)
    params % error_flag = 1
    params % error_message = "Not initialized"
end subroutine params_deinit

!> Adjust a guess for the number of Lebedev grid points.
!!
!! @param[inout] ngrid: Approximate number of Lebedev grid points on input and
!!      actual number of grid points on exit. `ngrid` >= 0
subroutine closest_supported_lebedev_grid(ngrid)
    integer, intent(inout) :: ngrid
    integer :: igrid, i, inear, jnear
    ! Get nearest number of Lebedev grid points
    igrid = 0
    inear = 100000
    do i = 1, nllg
        jnear = abs(ng0(i) - ngrid)
        if (jnear .lt. inear) then
            inear = jnear
            igrid = i
        end if
    end do
    ngrid = ng0(igrid)
end subroutine

!> Print error message and exit with provided error code
subroutine error(code, message)
    integer, intent(in) :: code
    character(len=*), intent(in) :: message
    write(0, "(A,A)") "ERROR: ", message
    write(0, "(A,A)") "CODE: ", code
    stop -1
end subroutine


!> Default printing function
subroutine print_func_default(string)
    character(len=255), intent(in) :: string
    print "(A)", string
end subroutine

end module ddx_parameters
