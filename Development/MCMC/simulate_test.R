library("JMbayes2")
simulateJoint <- function (alpha = 0.5, Dalpha = 0, n = 500, upp_Cens = 7) {
    K <- 15  # number of planned repeated measurements per subject, per outcome
    t.max <- upp_Cens # maximum follow-up time

    ################################################

    # parameters for the linear mixed effects model
    betas <- c("Intercept" = 6.94, "Time1" = 1.30, "Time2" = 1.84, "Time3" = 1.82)
    sigma.y <- 0.6 # measurement error standard deviation

    # parameters for the survival model
    gammas <- c("(Intercept)" = -9, "Group" = 0.5, "Age" = 0.05)
    phi <- 2

    D <- matrix(0, 4, 4)
    D[lower.tri(D, TRUE)] <- c(0.71, 0.33, 0.07, 1.26, 2.68, 3.81, 4.35, 7.62, 5.4, 8)
    D <- D + t(D)
    diag(D) <- diag(D) * 0.5

    ################################################

    Bkn <- c(0, 7)
    kn <- c(1, 3)

    # design matrices for the longitudinal measurement model
    times <- c(replicate(n, c(0, sort(runif(K - 1, 1, t.max)))))
    group <- rep(0:1, each = n/2)
    age <- runif(n, 30, 70)
    DF <- data.frame(time = times)
    X <- model.matrix(~ ns(time, knots = kn, Boundary.knots = Bkn),
                      data = DF)
    Z <- model.matrix(~ ns(time, knots = kn, Boundary.knots = Bkn), data = DF)

    # design matrix for the survival model
    W <- cbind("(Intercept)" = 1, "Group" = group, "Age" = age)

    ################################################

    # simulate random effects
    b <- MASS::mvrnorm(n, rep(0, nrow(D)), D)

    # simulate longitudinal responses
    id <- rep(1:n, each = K)
    eta.y <- as.vector(X %*% betas + rowSums(Z * b[id, ]))
    y <- rnorm(n * K, eta.y, sigma.y)

    # simulate event times
    eta.t <- as.vector(W %*% gammas)
    invS <- function (t, u, i) {
        h <- function (s) {
            NS <- ns(s, knots = kn, Boundary.knots = Bkn)
            DNS <- JMbayes:::dns(s, knots = kn, Boundary.knots = Bkn)
            XX <- cbind(1, NS)
            ZZ <- cbind(1, NS)
            XXd <- DNS
            ZZd <- DNS
            f1 <- as.vector(XX %*% betas + rowSums(ZZ * b[rep(i, nrow(ZZ)), ]))
            f2 <- as.vector(XXd %*% betas[2:4] + rowSums(ZZd * b[rep(i, nrow(ZZd)), 2:4]))
            exp(log(phi) + (phi - 1) * log(s) + eta.t[i] + f1 * alpha + f2 * Dalpha)
        }
        integrate(h, lower = 0, upper = t)$value + log(u)
    }
    u <- runif(n)
    trueTimes <- numeric(n)
    for (i in 1:n) {
        Up <- 50
        tries <- 5
        Root <- try(uniroot(invS, interval = c(1e-05, Up), u = u[i], i = i)$root, TRUE)
        while(inherits(Root, "try-error") && tries > 0) {
            tries <- tries - 1
            Up <- Up + 50
            Root <- try(uniroot(invS, interval = c(1e-05, Up), u = u[i], i = i)$root, TRUE)
        }
        trueTimes[i] <- if (!inherits(Root, "try-error")) Root else NA
    }
    na.ind <- !is.na(trueTimes)
    trueTimes <- trueTimes[na.ind]
    W <- W[na.ind, , drop = FALSE]
    long.na.ind <- rep(na.ind, each = K)
    y <- y[long.na.ind]
    X <- X[long.na.ind, , drop = FALSE]
    Z <- Z[long.na.ind, , drop = FALSE]
    DF <- DF[long.na.ind, , drop = FALSE]
    n <- length(trueTimes)

    Ctimes <- upp_Cens
    Time <- pmin(trueTimes, Ctimes)
    event <- as.numeric(trueTimes <= Ctimes) # event indicator

    ################################################

    # keep the nonmissing cases, i.e., drop the longitudinal measurements
    # that were taken after the observed event time for each subject.
    ind <- times[long.na.ind] <= rep(Time, each = K)
    y <- y[ind]
    X <- X[ind, , drop = FALSE]
    Z <- Z[ind, , drop = FALSE]
    id <- id[long.na.ind][ind]
    id <- match(id, unique(id))

    dat <- DF[ind, , drop = FALSE]
    dat$id <- id
    dat$y <- y
    dat$Time <- Time[id]
    dat$event <- event[id]
    dat <- dat[c("id", "y", "time", "Time", "event")]
    dat.id <- data.frame(id = unique(dat$id), Time = Time,
                         event = event, group = W[, 2], age = W[, 3])
    dat$group <- dat.id$group[id]

    #summary(tapply(id, id, length))
    #n
    #mean(event)
    #summary(dat.id$Time)
    #summary(dat$time)

    # true values for parameters and random effects
    trueValues <- list(betas = betas, sigmas = sigma.y, gammas = gammas[-1L],
                       alphas = alpha, Dalphas = Dalpha, sigma.t = phi,
                       D = D[lower.tri(D, TRUE)], b = b)

    # return list
    list(DF = dat, DF.id = dat.id, trueValues = trueValues)
}

################################################################################
################################################################################

M <- 20
Data <- simulateJoint()
res_bs_gammas <- matrix(as.numeric(NA), M, 12)
res_gammas <- matrix(as.numeric(NA), M, length(Data$trueValues$gammas))
res_alphas <- matrix(as.numeric(NA), M, length(Data$trueValues$alphas))
res_D <- matrix(as.numeric(NA), M, length(Data$trueValues$D))
res_betas <- matrix(as.numeric(NA), M, length(Data$trueValues$betas))
res_betas_lme <- matrix(as.numeric(NA), M, length(Data$trueValues$betas))
res_sigmas <- matrix(as.numeric(NA), M, length(Data$trueValues$sigmas))
times <- matrix(as.numeric(NA), M, 3)

for (m in seq_len(M)) {
    try_run <- try({
        Data <- simulateJoint()
        lmeFit <- lme(y ~ ns(time, knots = c(1, 3), Boundary.knots = c(0, 7)),
                      data = Data$DF,
                      random =
                          list(id = pdDiag(form =
                            ~ ns(time, knots = c(1, 3), Boundary.knots = c(0, 7)))),
                      control = lmeControl(opt = "optim"))
        coxFit <- coxph(Surv(Time, event) ~ group + age, data = Data$DF.id)

        obj <- jm(coxFit, list(lmeFit), time_var = "time")
    }, silent = TRUE)
    if (!inherits(try_run, "try-error")) {
        res_bs_gammas[m, ] <- obj$statistics$Mean$bs_gammas
        res_gammas[m, ] <- obj$statistics$Mean$gammas
        res_alphas[m, ] <- obj$statistics$Mean$alphas
        res_D[m, ] <- obj$statistics$Mean$D
        res_betas[m, ] <- obj$statistics$Mean$betas
        res_betas_lme[m, ] <- fixef(lmeFit)
        res_sigmas[m, ] <- obj$statistics$Mean$sigmas
        times[m, ] <- obj$running_time[1:3L]
    }
    print(m)
}

##########

colMeans(res_gammas, na.rm = TRUE) - Data$trueValues$gammas
colMeans(res_alphas, na.rm = TRUE) - Data$trueValues$alphas
colMeans(res_D, na.rm = TRUE) - Data$trueValues$D
colMeans(res_betas, na.rm = TRUE) - Data$trueValues$betas
colMeans(res_betas_lme, na.rm = TRUE) - Data$trueValues$betas
colMeans(res_sigmas, na.rm = TRUE) - Data$trueValues$sigmas

################################################################################
################################################################################

####################
# Beta mixed model #
####################


library("JMbayes2")
set.seed(1234)
n <- 200 # number of subjects
K <- 8 # number of measurements per subject
t_max <- 10 # maximum follow-up time

# we construct a data frame with the design:
# everyone has a baseline measurement, and then measurements at random follow-up times
DF <- data.frame(id = rep(seq_len(n), each = K),
                 time = c(replicate(n, c(0, sort(runif(K - 1, 0, t_max))))),
                 sex = rep(gl(2, n/2, labels = c("male", "female")), each = K))

# design matrices for the fixed and random effects
X <- model.matrix(~ sex * time, data = DF)
Z <- model.matrix(~ time, data = DF)

betas <- c(-2.2, -0.25, 0.24, -0.05) # fixed effects coefficients
phi <- 5 # precision parameter of the Beta distribution
D11 <- 1.0 # variance of random intercepts
D22 <- 0.5 # variance of random slopes

# we simulate random effects
b <- cbind(rnorm(n, sd = sqrt(D11)), rnorm(n, sd = sqrt(D22)))
# linear predictor
eta_y <- as.vector(X %*% betas + rowSums(Z * b[DF$id, ]))
# mean
mu_y <- plogis(eta_y) # exp(eta_y) / (1 + exp(eta_y))
# we simulate beta longitudinal data
DF$y <- rbeta(n * K, shape1 = mu_y * phi, shape2 = phi * (1 - mu_y))
# we transform to (0, 1)
DF$y <- (DF$y * (nrow(DF) - 1) + 0.5) / nrow(DF)

# simulate event times
upp_Cens <- 15 # fixed Type I censoring time
shape_wb <- 5 # shape Weibull
alpha <- 0.8 # association coefficients
gammas <- c("(Intercept)" = -9, "sex" = 0.5)
W <- model.matrix(~ sex, data = DF[!duplicated(DF$id), ])
eta_t <- as.vector(W %*% gammas)
invS <- function (t, i) {
    sex_i <- W[i, 2L]
    h <- function (s) {
        X_at_s <- cbind(1, sex_i, s, sex_i * s)
        Z_at_s <- cbind(1, s)
        f <- as.vector(X_at_s %*% betas +
                           rowSums(Z_at_s * b[rep(i, nrow(Z_at_s)), ]))
        exp(log(shape_wb) + (shape_wb - 1) * log(s) + eta_t[i] + f * alpha)
    }
    integrate(h, lower = 0, upper = t)$value + log(u[i])
}
u <- runif(n)
trueTimes <- numeric(n)
for (i in seq_len(n)) {
    Up <- 100
    Root <- try(uniroot(invS, interval = c(1e-05, Up), i = i)$root, TRUE)
    trueTimes[i] <- if (!inherits(Root, "try-error")) Root else 150
}

Ctimes <- upp_Cens
Time <- pmin(trueTimes, Ctimes)
event <- as.numeric(trueTimes <= Ctimes) # event indicator

# we keep the longitudinal measurements before the event times
DF$Time <- Time[DF$id]
DF$event <- event[DF$id]
DF <- DF[DF$time <= DF$Time, ]

# Fit the joint model
DF_id <- DF[!duplicated(DF$id), ]
Cox_fit <- coxph(Surv(Time, event) ~ sex, data = DF_id)
Beta_MixMod <- mixed_model(y ~ sex * time, random = ~ time | id, data = DF,
                           family = beta.fam())

jointFit <- jm(Cox_fit, Beta_MixMod, time_var = "time")
summary(jointFit)

################################################################################
################################################################################

#############################
# Beta-binomial mixed model #
#############################

library("JMbayes2")
set.seed(1234)
n <- 500 # number of subjects
K <- 8 # number of measurements per subject
t_max <- 10 # maximum follow-up time

# we construct a data frame with the design:
# everyone has a baseline measurement, and then measurements at random follow-up times
DF <- data.frame(id = rep(seq_len(n), each = K),
                 time = c(replicate(n, c(0, sort(runif(K - 1, 0, t_max))))),
                 sex = rep(gl(2, n/2, labels = c("male", "female")), each = K))

# design matrices for the fixed and random effects
X <- model.matrix(~ sex * time, data = DF)
Z <- model.matrix(~ time, data = DF)

betas <- c(-2.2, -0.25, 0.24, -0.05) # fixed effects coefficients
phi <- 5 # precision parameter of the Beta distribution
D11 <- 1.0 # variance of random intercepts
D22 <- 0.5 # variance of random slopes

# we simulate random effects
b <- cbind(rnorm(n, sd = sqrt(D11)), rnorm(n, sd = sqrt(D22)))
# linear predictor
eta_y <- as.vector(X %*% betas + rowSums(Z * b[DF$id, ]))
# mean
mu_y <- plogis(eta_y) # exp(eta_y) / (1 + exp(eta_y))
# we simulate probabilities from the Beta distribution
probs <- rbeta(n * K, shape1 = mu_y * phi, shape2 = phi * (1 - mu_y))
# we transform to (0, 1)
probs <- (probs * (nrow(DF) - 1) + 0.5) / nrow(DF)
# we simulate binomial data use the probs
DF$y <- rbinom(n * K, size = 20, prob = probs)

# simulate event times
upp_Cens <- 15 # fixed Type I censoring time
shape_wb <- 5 # shape Weibull
alpha <- 0.8 # association coefficients
gammas <- c("(Intercept)" = -9, "sex" = 0.5)
W <- model.matrix(~ sex, data = DF[!duplicated(DF$id), ])
eta_t <- as.vector(W %*% gammas)
invS <- function (t, i) {
    sex_i <- W[i, 2L]
    h <- function (s) {
        X_at_s <- cbind(1, sex_i, s, sex_i * s)
        Z_at_s <- cbind(1, s)
        f <- as.vector(X_at_s %*% betas +
                           rowSums(Z_at_s * b[rep(i, nrow(Z_at_s)), ]))
        exp(log(shape_wb) + (shape_wb - 1) * log(s) + eta_t[i] + f * alpha)
    }
    integrate(h, lower = 0, upper = t)$value + log(u[i])
}
u <- runif(n)
trueTimes <- numeric(n)
for (i in seq_len(n)) {
    Up <- 100
    Root <- try(uniroot(invS, interval = c(1e-05, Up), i = i)$root, TRUE)
    trueTimes[i] <- if (!inherits(Root, "try-error")) Root else 150
}

Ctimes <- upp_Cens
Time <- pmin(trueTimes, Ctimes)
event <- as.numeric(trueTimes <= Ctimes) # event indicator

# we keep the longitudinal measurements before the event times
DF$Time <- Time[DF$id]
DF$event <- event[DF$id]
DF <- DF[DF$time <= DF$Time, ]

# Fit the joint model
DF_id <- DF[!duplicated(DF$id), ]
Cox_fit <- coxph(Surv(Time, event) ~ sex, data = DF_id)
BetaBinom_MixMod <-
    mixed_model(cbind(y, 20 - y) ~ sex * time, random = ~ time | id, data = DF,
                family = beta.binomial())

jointFit <- jm(Cox_fit, BetaBinom_MixMod, time_var = "time")
summary(jointFit)

################################################################################
################################################################################

#####################
# Gamma mixed model #
#####################

library("JMbayes2")
set.seed(1234)
n <- 200 # number of subjects
K <- 8 # number of measurements per subject
t_max <- 10 # maximum follow-up time

# we construct a data frame with the design:
# everyone has a baseline measurement, and then measurements at random follow-up times
DF <- data.frame(id = rep(seq_len(n), each = K),
                 time = c(replicate(n, c(0, sort(runif(K - 1, 0, t_max))))),
                 sex = rep(gl(2, n/2, labels = c("male", "female")), each = K))

# design matrices for the fixed and random effects
X <- model.matrix(~ sex * time, data = DF)
Z <- model.matrix(~ time, data = DF)

betas <- c(2, -0.25, 0.24, -0.05) # fixed effects coefficients
phi <- 2 # scale of Gamma is mu_y / phi
D11 <- 1.0 # variance of random intercepts
D22 <- 0.5 # variance of random slopes

# we simulate random effects
b <- cbind(rnorm(n, sd = sqrt(D11)), rnorm(n, sd = sqrt(D22)))
# linear predictor
eta_y <- as.vector(X %*% betas + rowSums(Z * b[DF$id, ]))
# mean
mu_y <- exp(eta_y)
# we simulate beta longitudinal data
DF$y <- rgamma(n * K, shape = mu_y, scale = mu_y / phi)
DF$y[DF$y < sqrt(.Machine$double.eps)] <- 1e-05

# simulate event times
upp_Cens <- 15 # fixed Type I censoring time
alpha <- 0.8 # association coefficients
gammas <- c("(Intercept)" = -9, "sex" = 0.5)
W <- model.matrix(~ sex, data = DF[!duplicated(DF$id), ])
eta_t <- as.vector(W %*% gammas)
invS <- function (t, i) {
    sex_i <- W[i, 2L]
    h <- function (s) {
        X_at_s <- cbind(1, sex_i, s, sex_i * s)
        Z_at_s <- cbind(1, s)
        f <- as.vector(X_at_s %*% betas +
                           rowSums(Z_at_s * b[rep(i, nrow(Z_at_s)), ]))
        exp(log(phi) + (phi - 1) * log(s) + eta_t[i] + f * alpha)
    }
    integrate(h, lower = 0, upper = t)$value + log(u[i])
}
u <- runif(n)
trueTimes <- numeric(n)
for (i in seq_len(n)) {
    Up <- 100
    Root <- try(uniroot(invS, interval = c(1e-05, Up), i = i)$root, TRUE)
    trueTimes[i] <- if (!inherits(Root, "try-error")) Root else 150
}

Ctimes <- upp_Cens
Time <- pmin(trueTimes, Ctimes)
event <- as.numeric(trueTimes <= Ctimes) # event indicator

# we keep the longitudinal measurements before the event times
DF$Time <- Time[DF$id]
DF$event <- event[DF$id]
DF <- DF[DF$time <= DF$Time, ]

# Fit the joint model
DF_id <- DF[!duplicated(DF$id), ]
Cox_fit <- coxph(Surv(Time, event) ~ sex, data = DF_id)
Gamma_MixMod <- mixed_model(y ~ sex * time, random = ~ time | id, data = DF,
                           family = Gamma.fam())

jointFit <- jm(Cox_fit, Gamma_MixMod, time_var = "time")
summary(jointFit)


################################################################################
################################################################################

#################################
# Negative Binomial mixed model #
#################################

library("JMbayes2")
set.seed(1234)
n <- 500 # number of subjects
K <- 10 # number of measurements per subject
t_max <- 5 # maximum follow-up time

# we construct a data frame with the design:
# everyone has a baseline measurement, and then measurements at random follow-up times
DF <- data.frame(id = rep(seq_len(n), each = K),
                 time = c(replicate(n, c(0, sort(runif(K - 1, 0, t_max))))),
                 sex = rep(gl(2, n/2, labels = c("male", "female")), each = K))

# design matrices for the fixed and random effects non-zero part
X <- model.matrix(~ sex * time, data = DF)
Z <- model.matrix(~ time, data = DF)

betas <- c(0.8, -0.5, 0.8, -0.5) # fixed effects coefficients
shape <- 2 # shape/size parameter of the negative binomial distribution
D11 <- 1.0 # variance of random intercepts
D22 <- 0.3 # variance of random slopes

# we simulate random effects
b <- cbind(rnorm(n, sd = sqrt(D11)), rnorm(n, sd = sqrt(D22)))
# linear predictor non-zero part
eta_y <- as.vector(X %*% betas + rowSums(Z * b[DF$id, ]))
# we simulate negative binomial longitudinal data
DF$y <- rnbinom(n * K, size = shape, mu = exp(eta_y))

# simulate event times
upp_Cens <- 5 # fixed Type I censoring time
shape_wb <- 5 # shape Weibull
alpha <- 0.8 # association coefficients
gammas <- c("(Intercept)" = -9, "sex" = 0.5)
W <- model.matrix(~ sex, data = DF[!duplicated(DF$id), ])
eta_t <- as.vector(W %*% gammas)
invS <- function (t, i) {
    sex_i <- W[i, 2L]
    h <- function (s) {
        X_at_s <- cbind(1, sex_i, s, sex_i * s)
        Z_at_s <- cbind(1, s)
        f <- as.vector(X_at_s %*% betas +
                           rowSums(Z_at_s * b[rep(i, nrow(Z_at_s)), ]))
        exp(log(shape_wb) + (shape_wb - 1) * log(s) + eta_t[i] + f * alpha)
    }
    integrate(h, lower = 0, upper = t)$value + log(u[i])
}
u <- runif(n)
trueTimes <- numeric(n)
for (i in seq_len(n)) {
    Up <- 100
    Root <- try(uniroot(invS, interval = c(1e-05, Up), i = i)$root, TRUE)
    trueTimes[i] <- if (!inherits(Root, "try-error")) Root else 150
}

Ctimes <- upp_Cens
Time <- pmin(trueTimes, Ctimes)
event <- as.numeric(trueTimes <= Ctimes) # event indicator

# we keep the longitudinal measurements before the event times
DF$Time <- Time[DF$id]
DF$event <- event[DF$id]
DF <- DF[DF$time <= DF$Time, ]

# Fit the joint model
DF_id <- DF[!duplicated(DF$id), ]
Cox_fit <- coxph(Surv(Time, event) ~ sex, data = DF_id)
NB_MixMod <- mixed_model(y ~ sex * time, random = ~ time | id, data = DF,
                         family = negative.binomial())

jointFit <- jm(Cox_fit, NB_MixMod, time_var = "time")
summary(jointFit)

################################################################################
################################################################################

###############################
# Censored normal mixed model #
###############################

library("JMbayes2")
set.seed(1234)
n <- 200 # number of subjects
K <- 12 # number of measurements per subject
t_max <- 14 # maximum follow-up time

# we construct a data frame with the design:
# everyone has a baseline measurement, and then measurements at random follow-up times
DF <- data.frame(id = rep(seq_len(n), each = K),
                 time = c(replicate(n, c(0, sort(runif(K - 1, 0, t_max))))),
                 sex = rep(gl(2, n/2, labels = c("male", "female")), each = K))

# design matrices for the fixed and random effects
X <- model.matrix(~ sex * time, data = DF)
Z <- model.matrix(~ time, data = DF)

betas <- c(-2.2, -0.25, 0.24, -0.05) # fixed effects coefficients
sigma <- 0.5 # error standard deviation
D11 <- 1.0 # variance of random intercepts
D22 <- 0.5 # variance of random slopes

# we simulate random effects
b <- cbind(rnorm(n, sd = sqrt(D11)), rnorm(n, sd = sqrt(D22)))
# linear predictor
eta_y <- as.vector(X %*% betas + rowSums(Z * b[DF$id, ]))
# mean
mu_y <- eta_y
# we simulate normal longitudinal data
DF$y <- rnorm(n * K, mean = mu_y, sd = sigma)
# we assume that values below -4 are not observed, and set equal to -4
DF$ind <- as.numeric(DF$y < -4)
DF$y <- pmax(DF$y, -4)

# simulate event times
upp_Cens <- 15 # fixed Type I censoring time
shape_wb <- 5 # shape Weibull
alpha <- 0.8 # association coefficients
gammas <- c("(Intercept)" = -9, "sex" = 0.5)
W <- model.matrix(~ sex, data = DF[!duplicated(DF$id), ])
eta_t <- as.vector(W %*% gammas)
invS <- function (t, i) {
    sex_i <- W[i, 2L]
    h <- function (s) {
        X_at_s <- cbind(1, sex_i, s, sex_i * s)
        Z_at_s <- cbind(1, s)
        f <- as.vector(X_at_s %*% betas +
                           rowSums(Z_at_s * b[rep(i, nrow(Z_at_s)), ]))
        exp(log(shape_wb) + (shape_wb - 1) * log(s) + eta_t[i] + f * alpha)
    }
    integrate(h, lower = 0, upper = t)$value + log(u[i])
}
u <- runif(n)
trueTimes <- numeric(n)
for (i in seq_len(n)) {
    Up <- 100
    Root <- try(uniroot(invS, interval = c(1e-05, Up), i = i)$root, TRUE)
    trueTimes[i] <- if (!inherits(Root, "try-error")) Root else 150
}

Ctimes <- upp_Cens
Time <- pmin(trueTimes, Ctimes)
event <- as.numeric(trueTimes <= Ctimes) # event indicator

# we keep the longitudinal measurements before the event times
DF$Time <- Time[DF$id]
DF$event <- event[DF$id]
DF <- DF[DF$time <= DF$Time, ]

# Fit the joint model
DF_id <- DF[!duplicated(DF$id), ]
Cox_fit <- coxph(Surv(Time, event) ~ sex, data = DF_id)
CensNorm_MixMod <-
    mixed_model(cbind(y, ind) ~ sex * time, random = ~ time | id, data = DF,
                family = censored.normal())

jointFit <- jm(Cox_fit, CensNorm_MixMod, time_var = "time")
summary(jointFit)

Surv_object = Cox_fit
Mixed_objects = CensNorm_MixMod
time_var = "time"
functional_forms = NULL
data_Surv = NULL
id_var = NULL
priors = NULL
control = NULL


