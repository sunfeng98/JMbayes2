# This script contais the R functions that will need to be translated to C++

linpred_mixed <- function (X, betas, Z, b, id) {
    n_outcomes <- length(X)
    out <- vector("list", n_outcomes)
    for (i in seq_len(n_outcomes)) {
        X_i <- X[[i]]
        betas_i <- betas[[i]]
        Z_i <- Z[[i]]
        b_i <- b[[i]]
        id_i <- id[[i]]
        out[[i]] <- X_i %*% betas_i + rowSums(Z_i * b_i[id_i, ])
    }
    out
}

log_dens_Funs <- function (family) {
    gaussian_log_dens <- function (y, eta, mu_fun = NULL, phis, eta_zi = NULL) {
        dnorm(y, eta, exp(phis), log = TRUE)
    }
    switch(family$family,
           "gaussian" = gaussian_log_dens,
           "binomial" = GLMMadaptive:::binomial_log_dens,
           "poisson" = GLMMadaptive:::poisson_log_dens,
           "negative.binomial" = GLMMadaptive:::negative.binomial_log_dens)
}

log_density_mixed <- function (y, linear_predictor, log_sigmas, Funs, mu_funs,
                               nY, unq_idL, idL_lp) {
    n_outcomes <- length(y)
    out <- matrix(0.0, nY, 1)
    for (i in seq_len(n_outcomes)) {
        y_i <- y[[i]]
        eta_i <- linear_predictor[[i]]
        log_sigma_i <- log_sigmas[[i]]
        id_i <- unq_idL[[i]]
        id_lp_i <- idL_lp[[i]]
        # Consideration for C++ implementation: The above can be transformed from a
        # list in R to a field of RcppArmadillo. However, this cannot be done for
        # functions, i.e., you cannot have a field of functions. Logically, it will be
        # costly to extract each time the R function from the list in C++. Perhaps then
        # all these functions, i.e., the log densities for each family and the inverse
        # link functions will need to be implemented in C++.
        log_dens_i <- Funs[[i]] # <--------
        mu_fun_i <- mu_funs[[i]] # <---------
        out[id_i, ] <- out[id_i, ] + rowsum(log_dens_i(y_i, eta_i, mu_fun_i, log_sigma_i),
                                            id_lp_i, reorder = FALSE)
    }
    unname(out)
}

linpred_surv <- function (X, betas, Z, b, id) {
    out <- vector("list", length(X))
    for (i in seq_along(X)) {
        X_i <- X[[i]]
        Z_i <- Z[[i]]
        betas_i <- betas[[i]]
        b_i <- b[[i]]
        id_i <- id[[i]]
        out[[i]] <- matrix(0.0, nrow = nrow(X_i[[1]]), ncol = length(X_i))
        for (j in seq_along(X_i)) {
            X_ij <- X_i[[j]]
            Z_ij <- Z_i[[j]]
            out[[i]][, j] <- X_ij %*% betas_i + rowSums(Z_ij * b_i[id_i, ])
        }
    }
    out
}

create_Wlong <- function (eta, functional_forms_per_outcome, U) {
    Wlong <- vector("list", length(eta))
    for (i in seq_along(functional_forms_per_outcome)) {
        FF_i <- functional_forms_per_outcome[[i]]
        eta_i <- eta[[i]]
        U_i <- U[[i]]
        Wlong_i <- matrix(1.0, nrow(eta_i), max(unlist(FF_i)))
        for (j in seq_along(FF_i)) {
            ind <- FF_i[[j]]
            Wlong_i[, ind] <- Wlong_i[, ind] * eta_i[, j]
        }
        Wlong[[i]] <- U_i * Wlong_i
    }
    Wlong
}

calculate_u <- function (Xhc, columns_HC, betas, b, unq_idL) {
    u <- b
    for (i in seq_along(Xhc)) {
        Xhc_i <- Xhc[[i]]
        columns_HC_i <- columns_HC[[i]]
        betas_i <- betas[[i]]
        b_i <- b[[i]]
        unq_idL_i <- unq_idL[[i]]
        mean_b_i <- b_i * 0
        for (j in seq_len(ncol(b_i))) {
            index <- columns_HC_i == j
            mean_b_i[unq_idL_i, j] <- c(Xhc_i[, index, drop = FALSE] %*% betas_i[index])
        }
        u[[i]] <- b_i + mean_b_i
    }
    u
}






