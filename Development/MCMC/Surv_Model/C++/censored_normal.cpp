#include <RcppArmadillo.h>
// [[Rcpp::depends("RcppArmadillo")]]

using namespace Rcpp;
using namespace arma;

static double const Const_Unif_Proposal = 0.5 * std::pow(12.0, 0.5);
static double const log2pi = std::log(2.0 * M_PI);

vec log_dnorm (const vec &x, const vec &mu, const double &sigma) {
    vec sigmas(x.n_rows);
    sigmas.fill(sigma);
    vec out = log_normpdf(x, mu, sigmas);
    return out;
}

vec log_pnorm (const vec &x, const vec &mu, const double &sigma,
               const int lower_tail = 1) {
    uword n = x.n_rows;
    vec out(n);
    for (uword i = 0; i < n; ++i) {
        out.at(i) = R::pnorm(x.at(i), mu.at(i), sigma, lower_tail, 1);
    }
    return out;
}

// [[Rcpp::export]]
vec log_long_i (const mat &y_i, const vec &eta_i, const double &sigma_i) {
    uword N = y_i.n_rows;
    vec log_contr(N);
    uvec ind0 = find(y_i.col(1) == 0);
    uvec ind1 = find(y_i.col(1) == 1);
    uvec ind2 = find(y_i.col(1) == 2);
    vec yy = y_i.col(0);
    log_contr.rows(ind0) = log_dnorm(yy.rows(ind0), eta_i.rows(ind0), sigma_i);
    log_contr.rows(ind1) = log_pnorm(yy.rows(ind1), eta_i.rows(ind1), sigma_i);
    log_contr.rows(ind2) = log_pnorm(yy.rows(ind2), eta_i.rows(ind2), sigma_i, 0);
    return log_contr;
}

// [[Rcpp::export]]
vec logPrior(const vec &x, const vec &mean) {
    vec z = (x - mean);
    return z.ones();
}


// [[Rcpp::export]]
vec test_chol1 (const mat &Tau, const vec &mu) {
    mat U = chol(Tau);
    vec m1 = solve(trimatl(U.t()), mu);
    vec mean = solve(trimatu(U), m1);
    return mean;
}

// [[Rcpp::export]]
vec test_chol2 (const mat &Tau, const vec &mu) {
    vec mean = solve(Tau, mu);
    return mean;
}

// [[Rcpp::export]]
field<mat> create_storage (const field<vec> &F, const uword &n_iter) {
    uword n = F.size();
    field<mat> out(n);
    for (uword i = 0; i < n; ++i) {
        vec aa = F.at(i);
        uword n_i = aa.n_rows;
        mat tt(n_iter, n_i, fill::zeros);
        out.at(i) = tt;
    }
    return out;
}




