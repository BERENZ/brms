# All functions in this file have the same arguments structure
#
# Args:
#  n: the column of samples to use i.e. the nth obervation in the initial data.frame 
#  data: the data as passed to Stan
#  samples: samples obtained through Stan. Must at least contain variable eta
#  link: the link function
#
# Returns:
#   A vector of length nrow(samples) containing the pointwise log-likelihood for the nth observation 
loglik_gaussian <- function(n, data, samples, link) {
  sigma <- if (!is.null(samples$sigma)) samples$sigma
           else data$sigma
  args <- list(mean = ilink(samples$eta[, n], link), sd = sigma)
  # censor_loglik computes the conventional loglik in case of no censoring 
  out <- censor_loglik(dist = "norm", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pnorm, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_student <- function(n, data, samples, link) {
  sigma <- if (!is.null(samples$sigma)) samples$sigma
           else data$sigma
  args <- list(df = samples$nu, mu = ilink(samples$eta[, n], link), 
               sigma = sigma)
  out <- censor_loglik(dist = "student", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pstudent, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_cauchy <- function(n, data, samples, link) {
  sigma <- if (!is.null(samples$sigma)) samples$sigma
           else data$sigma
  args <- list(df = 1, mu = ilink(samples$eta[, n], link), 
               sigma = sigma)
  out <- censor_loglik(dist = "student", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pstudent, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_lognormal <- function(n, data, samples, link) {
  # link is currently ignored for lognormal models
  # as 'identity' is the only valid link
  sigma <- if (!is.null(samples$sigma)) samples$sigma
           else data$sigma
  args <- list(meanlog = samples$eta[, n], sdlog = sigma)
  out <- censor_loglik(dist = "lnorm", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = plnorm, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_multinormal <- function(n, data, samples, link) {
  nobs <- data$N_trait * data$K_trait
  out <- sapply(1:nrow(samples$eta), function(i) 
    dmultinormal(data$Y[n,], Sigma = samples$Sigma[i, , ], log = TRUE,
                 mu = samples$eta[i, seq(n, nobs, data$N_trait)]))
  # no truncation allowed
  weight_loglik(out, n = n, data = data)
}

loglik_binomial <- function(n, data, samples, link) {
  trials <- ifelse(length(data$max_obs) > 1, data$max_obs[n], data$max_obs) 
  args <- list(size = trials, prob = ilink(samples$eta[, n], link))
  out <- censor_loglik(dist = "binom", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pbinom, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}  

loglik_bernoulli <- function(n, data, samples, link) {
  out <- censor_loglik(dist = "binom", args = args, n = n, data = data)
  # no truncation allowed
  weight_loglik(out, n = n, data = data)
}

loglik_poisson <- function(n, data, samples, link) {
  args <- list(lambda = ilink(samples$eta[, n], link))
  out <- censor_loglik(dist = "pois", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = ppois, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_negbinomial <- function(n, data, samples, link) {
  args <- list(mu = ilink(samples$eta[, n], link), size = samples$shape)
  out <- censor_loglik(dist = "nbinom", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pnbinom, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_geometric <- function(n, data, samples, link) {
  args <- list(mu = ilink(samples$eta[, n], link), size = 1)
  out <- censor_loglik(dist = "nbinom", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pnbinom, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_exponential <-  function(n, data, samples, link) {
  args <- list(rate = ilink(-samples$eta[, n], link))
  out <- censor_loglik(dist = "exp", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pexp, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_gamma <- function(n, data, samples, link) {
  args <- list(shape = samples$shape,
               scale = ilink(samples$eta[, n], link) / samples$shape)
  out <- censor_loglik(dist = "gamma", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pgamma, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_weibull <- function(n, data, samples, link) {
  args <- list(shape = samples$shape,
               scale = 1 / (ilink(-samples$eta[, n] / samples$shape, link)))
  out <- censor_loglik(dist = "weibull", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pweibull, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_inverse.gaussian <- function(n, data, samples, link) {
  args <- list(mean = ilink(samples$eta[, n], link), shape = samples$shape)
  out <- censor_loglik(dist = "invgauss", args = args, n = n, data = data)
  out <- truncate_loglik(out, cdf = pinvgauss, args = args, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_hurdle_poisson <- function(n, data, samples, link) {
  theta <- ilink(samples$eta[, n + data$N_trait], "logit")
  args <- list(lambda = ilink(samples$eta[, n], link))
  out <- hurdle_loglik(pdf = dpois, theta = theta, 
                       args = args, n = n, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_hurdle_negbinomial <- function(n, data, samples, link) {
  theta <- ilink(samples$eta[, n + data$N_trait], "logit")
  args <- list(mu = ilink(samples$eta[, n], link), size = samples$shape)
  out <- hurdle_loglik(pdf = dnbinom, theta = theta, 
                       args = args, n = n, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_hurdle_gamma <- function(n, data, samples, link) {
  theta <- ilink(samples$eta[, n + data$N_trait], "logit")
  args <- list(shape = samples$shape, 
               scale = ilink(samples$eta[, n], link) / samples$shape)
  out <- hurdle_loglik(pdf = dgamma, theta = theta, 
                       args = args, n = n, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_zero_inflated_poisson <- function(n, data, samples, link) {
  theta <- ilink(samples$eta[, n + data$N_trait], "logit")
  args <- list(lambda = ilink(samples$eta[, n], link))
  out <- zero_inflated_loglik(pdf = dpois, theta = theta, 
                              args = args, n = n, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_zero_inflated_negbinomial <- function(n, data, samples, link) {
  theta <- ilink(samples$eta[, n + data$N_trait], "logit")
  args <- list(mu = ilink(samples$eta[, n], link), size = samples$shape)
  out <- zero_inflated_loglik(pdf = dnbinom, theta = theta, 
                              args = args, n = n, data = data)
  weight_loglik(out, n = n, data = data)
}

loglik_categorical <- function(n, data, samples, link) {
  ncat <- ifelse(length(data$max_obs) > 1, data$max_obs[n], data$max_obs) 
  if (link == "logit") {
    p <- cbind(rep(0, nrow(samples$eta)), samples$eta[, n, 1:(ncat - 1)])
    out <- p[,data$Y[n]] - log(rowSums(exp(p)))
  } else stop(paste("Link", link, "not supported"))
  weight_loglik(out, n = n, data = data)
}

loglik_cumulative <- function(n, data, samples, link) {
  ncat <- ifelse(length(data$max_obs) > 1, data$max_obs[n], data$max_obs) 
  y <- data$Y[n]
  if (y == 1) { 
    out <- log(ilink(samples$eta[, n, 1], link))
  } else if (y == ncat) {
    out <- log(1 - ilink(samples$eta[, n, y - 1], link)) 
  } else {
    out <- log(ilink(samples$eta[, n, y], link) - 
                  ilink(samples$eta[, n, y - 1], link))
  }
  weight_loglik(out, n = n, data = data)
}

loglik_sratio <- function(n, data, samples, link) {
  ncat <- ifelse(length(data$max_obs) > 1, data$max_obs[n], data$max_obs) 
  y <- data$Y[n]
  q <- sapply(1:min(y, ncat - 1), function(k) 
    1 - ilink(samples$eta[, n, k], link))
  if (y == 1) {
    out <- log(1 - q[, 1]) 
  } else if (y == 2) {
    out <- log(1 - q[, 2]) + log(q[, 1])
  } else if (y == ncat) {
    out <- rowSums(log(q))
  } else {
    out <- log(1 - q[, y]) + rowSums(log(q[, 1:(y - 1)]))
  }
  weight_loglik(out, n = n, data = data)
}

loglik_cratio <- function(n, data, samples, link) {
  ncat <- ifelse(length(data$max_obs) > 1, data$max_obs[n], data$max_obs) 
  y <- data$Y[n]
  q <- sapply(1:min(y, ncat-1), function(k) 
    ilink(samples$eta[, n, k], link))
  if (y == 1) {
    out <- log(1 - q[, 1])
  }  else if (y == 2) {
    out <- log(1 - q[, 2]) + log(q[, 1])
  } else if (y == ncat) {
    out <- rowSums(log(q))
  } else {
    out <- log(1 - q[, y]) + rowSums(log(q[, 1:(y - 1)]))
  }
  weight_loglik(out, n = n, data = data)
}

loglik_acat <- function(n, data, samples, link) {
  ncat <- ifelse(length(data$max_obs) > 1, data$max_obs[n], data$max_obs) 
  y <- data$Y[n]
  if (link == "logit") { # more efficient calculation 
    q <- sapply(1:(ncat - 1), function(k) samples$eta[, n, k])
    p <- cbind(rep(0, nrow(samples$eta)), q[, 1], 
               matrix(0, nrow = nrow(samples$eta), ncol = ncat - 2))
    if (ncat > 2) {
      p[, 3:ncat] <- sapply(3:ncat, function(k) rowSums(q[, 1:(k - 1)]))
    }
    out <- p[, y] - log(rowSums(exp(p)))
  } else {
    q <- sapply(1:(ncat - 1), function(k) 
      ilink(samples$eta[,n , k], link))
    p <- cbind(apply(1 - q[, 1:(ncat - 1)], 1, prod), 
               matrix(0, nrow = nrow(samples$eta), ncol = ncat - 1))
    if (ncat > 2) {
      p[, 2:(ncat - 1)] <- sapply(2:(ncat - 1), function(k) 
        apply(as.matrix(q[, 1:(k - 1)]), 1, prod) * 
          apply(as.matrix(1 - q[, k:(ncat - 1)]), 1, prod))
    }
    p[, ncat] <- apply(q[, 1:(ncat - 1)], 1, prod)
    out <- log(p[, y]) - log(apply(p, 1, sum))
  }
  weight_loglik(out, n = n, data = data)
}

#---------------loglik helper-functions----------------------------

censor_loglik <- function(dist, args, n, data) {
  # compute (possibly censored) loglik values
  # Args:
  #   dist: name of a distribution for which the functions
  #         d<dist> (pdf) and p<dist> (cdf) are available
  #   args: additional arguments passed to pdf and cdf
  #   data: data initially passed to Stan
  # Returns:
  #   vector of loglik values
  pdf <- get(paste0("d", dist), mode = "function")
  cdf <- get(paste0("p", dist), mode = "function")
  if (is.null(data$cens) || data$cens[n] == 0) {
    do.call(pdf, c(data$Y[n], args, log = TRUE))
  } else if (data$cens[n] == 1) {
    do.call(cdf, c(data$Y[n], args, lower.tail = FALSE, log.p = TRUE))
  } else if (data$cens[n] == -1) {
    do.call(cdf, c(data$Y[n], args, log.p = TRUE))
  }
}

truncate_loglik <- function(x, cdf, args, data) {
  # adjust logLik in truncated models
  # Args:
  #  x: vector of loglik values
  #  cdf: a cumulative distribution function 
  #  args: arguments passed to cdf
  #  data: data initially passed to Stan
  # Returns:
  #   vector of loglik values
  if (!(is.null(data$lb) && is.null(data$ub))) {
    lb <- ifelse(is.null(data$lb), -Inf, data$lb)
    ub <- ifelse(is.null(data$ub), Inf, data$ub)
    x - log(do.call(cdf, c(ub, args)) - do.call(cdf, c(lb, args)))
  } else {
    x
  }
}

weight_loglik <- function(x, n, data) {
  # weight loglik values according to defined weights
  # Args:
  #  x: vector of loglik values
  #  n: observation number
  #  data: data initially passed to Stan
  # Returns:
  #   vector of loglik values
  if ("weights" %in% names(data)) {
    x * data$weights[n]
  } else {
    x
  }
}

hurdle_loglik <- function(pdf, theta, args, n, data) {
  # loglik values for hurdle modles
  # Args:
  #  pdf: a probability density function 
  #  theta: bernoulli hurdle parameter
  #  args: arguments passed to pdf
  #  data: data initially passed to Stan
  # Returns:
  #   vector of loglik values
  if (data$Y[n] == 0) {
    dbinom(1, size = 1, prob = theta, log = TRUE)
  } else {
    dbinom(0, size = 1, prob = theta, log = TRUE) + 
      do.call(pdf, c(data$Y[n], args, log = TRUE))
  }
}

zero_inflated_loglik <- function(pdf, theta, args, n, data) {
  # loglik values for zero-inflated models
  # Args:
  #  pdf: a probability density function 
  #  theta: bernoulli zero-inflation parameter
  #  args: arguments passed to pdf
  #  data: data initially passed to Stan
  # Returns:
  #   vector of loglik values
  if (data$Y[n] == 0) {
    log(dbinom(1, size = 1, prob = theta) + 
        dbinom(0, size = 1, prob = theta) *
          do.call(pdf, c(0, args)))
  } else {
    dbinom(0, size = 1, prob = theta, log = TRUE) +
      do.call(pdf, c(data$Y[n], args, log = TRUE))
  }
}