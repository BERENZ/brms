#' @export
parnames.brmsfit <- function(x, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  dimnames(x$fit)$parameters
}


#' @export
fixef.brmsfit <-  function(x, estimate = "mean", ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  pars <- parnames(x)
  fpars <- pars[grepl("^b_", pars)]
  if (!length(fpars)) stop(paste("No fixed effect present in argument x")) 
  out <- posterior_samples(x, parameters = fpars, exact_match = TRUE)
  out <- do.call(cbind, lapply(estimate, get_estimate, samples = out, ...))
  rownames(out) <- gsub("^b_", "", fpars)
  out
}

#' @export
ranef.brmsfit <- function(x, estimate = "mean", var = FALSE, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (!estimate %in% c("mean","median"))
    stop("Argument estimate must be either 'mean' or 'median'")
  if (!length(x$ranef))
    stop("The model does not contain random effects")
  group <- names(x$ranef)
  pars <- parnames(x)
  
  ranef <- lapply(1:length(group), function(i) {
    g <- group[i]
    rnames <- x$ranef[[i]]
    rpars <- pars[grepl(paste0("^r_",group[i],"\\["), pars)]
    if (!length(rpars))
      stop(paste0("The model does not contain random effects for group '",g,"'\n",
                  "You should use argument ranef = TRUE in function brm."))
    rdims <- x$fit@sim$dims_oi[[paste0("r_",group[i])]]
    rs <- posterior_samples(x, parameters = rpars, exact_match = TRUE)
    ncol <- ifelse(is.na(rdims[2]), 1, rdims[2])
    rs_array <- array(dim = c(rdims[1], ncol, nrow(rs)))
    k <- 0
    for (j in 1:ncol) {
      for (i in 1:rdims[1]) {
        k <- k + 1
        rs_array[i,j,] <- rs[,k]
      }
    }
    out <- get_estimate(estimate, samples = rs_array, margin = 1:2, ...)
    colnames(out) <- rnames
    if(var) {
      Var <- array(dim = c(rep(ncol, 2), rdims[1]), 
                   dimnames = list(rnames, rnames, 1:rdims[1]))
      for (i in 1:rdims[1]) {
        if (is.na(rdims[2])) Var[,,i] <- var(rs_array[i,1,]) 
        else Var[,,i] <- cov(t(rs_array[i,,])) 
      }
      attr(out, "var") <- Var
    }
    out
  })
  names(ranef) <- group
  ranef 
} 

#' @export
VarCorr.brmsfit <- function(x, estimate = "mean", as.list = TRUE, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (!(length(x$ranef) || x$family %in% c("gaussian", "student", "cauchy")))
    stop("The model does not contain covariance matrices")

  # extracts samples for sd, cor and cov
  extract <- function(p) {
    nr <- length(p$sd_pars)
    sd <- posterior_samples(x, parameters = p$sd_pars, exact_match = TRUE)
    nsamples <- nrow(sd)
    out <- list(sd = do.call(cbind, lapply(estimate, get_estimate, samples = sd, ...)))
    rownames(out$sd) <- p$rnames 
    
    # calculate correlation and covariance matrices
    found_cor_pars <- intersect(p$cor_pars, parnames(x))
    if (length(found_cor_pars)) {
      cor <- posterior_samples(x, parameters = paste0("^",found_cor_pars,"$"))
      if (length(found_cor_pars) < length(p$cor_pars)) { # some correlations are missing
        cor_all <- as.data.frame(matrix(0, nrow = nrow(cor), ncol = length(p$cor_pars)))
        names(cor_all) <- p$cor_pars
        for (i in 1:ncol(cor_all)) {
          found <- match(names(cor_all)[i], names(cor))
          if (!is.na(found)) # correlation was estimated
            cor_all[, i] <- cor[, found]
        }
        cor <- cor_all
      }
    } else cor <- NULL
    # get_cov_matrix, list2arry, and array2list can be found in misc.R
    matrices <- get_cov_matrix(sd = sd, cor = cor) 
    out$cor <- list2array(lapply(estimate, get_estimate, samples = matrices$cor, 
                          margin = c(2,3), to.array = TRUE, ...))
    out$cov <- list2array(lapply(estimate, get_estimate, samples = matrices$cov, 
                          margin = c(2,3), to.array = TRUE, ...)) 
    if (length(p$rnames) > 1)
      dimnames(out$cov) <- dimnames(out$cor) <- list(p$rnames, p$rnames, dimnames(out$cor)[[3]])
    if (as.list) {
      out$cor <- lapply(array2list(out$cor), function(x)
        if (is.null(dim(x))) structure(matrix(x), dimnames = list(p$rnames, p$rnames)) else x)
      out$cov <- lapply(array2list(out$cov), function(x)
        if (is.null(dim(x))) structure(matrix(x), dimnames = list(p$rnames, p$rnames)) else x)
    }
    out
  }
  
  ee <- extract_effects(x$formula, family = x$family)
  if (length(x$ranef)) {
    group <- names(x$ranef)
    p <- lapply(1:length(group), function(i)
      list(rnames = x$ranef[[i]],
           type = paste0("cor_",group[i]),
           sd_pars = paste0("sd_",group[i],"_",x$ranef[[i]]),
           cor_pars = get_cornames(x$ranef[[i]], type = paste0("cor_",group[i]), 
                                   brackets = FALSE)))
  } else p <- group <- NULL
  if (x$family %in% c("gaussian", "student", "cauchy") && !is.formula(ee$se)) {
    p[[length(p)+1]] <- list(rnames = ee$response, 
                             type = "rescor",
                             sd_pars = paste0("sigma_",ee$response),
                             cor_pars = get_cornames(ee$response, type = "rescor", 
                                                     brackets = FALSE))
    group <- c(group, "RESIDUAL")
  } 
  VarCorr <- lapply(p, extract)
  names(VarCorr) <- group
  VarCorr
}

#' @export
posterior_samples.brmsfit <- function(x, parameters = NA, exact_match = FALSE, add_chains = FALSE, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  pars <- parnames(x)
  if (!(anyNA(parameters) || is.character(parameters))) 
    stop("Argument parameters must be NA or a character vector")
  if (!anyNA(parameters)) {
    if (exact_match) pars <- pars[pars %in% parameters]
    else pars <- pars[apply(sapply(parameters, grepl, x = pars, ...), 1, any)]
  } 
  
  iter <- attr(x$fit@sim$samples[[1]],"args")$iter
  warmup <- attr(x$fit@sim$samples[[1]],"args")$warmup
  thin <- attr(x$fit@sim$samples[[1]],"args")$thin
  chains <- length(x$fit@sim$samples) 
  
  if (length(pars)) {
    samples <- data.frame(sapply(1:length(pars), function(i)
      unlist(lapply(1:chains, function(j) 
        x$fit@sim$samples[[j]][[pars[i]]][(warmup/thin+1):(iter/thin)]))))
    names(samples) <- pars
    if (add_chains) {
      samples$chains <- factor(do.call(c, lapply(1:chains, rep, times = nrow(samples)/chains)))
      samples$iter <- rep((warmup+1):(nrow(samples)/chains+warmup), chains)
    }
  } else samples <- NULL  
  samples
}

#' @export
prior_samples.brmsfit <- function(x, parameters = NA, ...) {
  if (!anyNA(parameters) && !is.character(parameters)) 
    stop("pars must be a character vector")
  par_names <- parnames(x)
  prior_names <- par_names[grepl("^prior_", par_names)]
  if (length(prior_names)) {
    samples <- posterior_samples(x, parameters = prior_names, exact_match = TRUE)
    names(samples) <- sub("^prior_", "", prior_names)
    if (!anyNA(parameters)) {
      samples <- data.frame(rmNULL(lapply(parameters, function(par) {
        matches <- lapply(paste0("^",sub("^prior_", "", prior_names)), regexpr, text = par)
        matches <- unlist(lapply(matches, attr, which = "match.length"))
        if (max(matches) == -1) NULL
        else structure(list(samples[,match(max(matches), matches)]), names = par)
      })), check.names = FALSE)
    }
  }
  else samples <- NULL
  samples
}

#' Print a summary for a fitted model represented by a \code{brmsfit} object
#'
#' Print basic information regarding the fitted model and a summary for the fixed and random effects
#' estimated by the samples included in a \code{brmsfit} object.
#' 
#' @aliases print.brmssummary
#' 
#' @param x An object of class \code{brmsfit}
#' @param digits The number of significant digits for printing out the summary; defaults to 2. 
#'   The effective sample size is always rounded to integers.
#' @param ... Additional arguments that would be passed to method \code{summary} of \code{brmsfit}.
#'
#' @author Paul-Christian Buerkner \email{paul.buerkner@@gmail.com}
#' 
#' @export
print.brmsfit <- function(x, digits = 2, ...) {
  print(summary(x), digits = digits, ...)
}  

#' Create a summary of a fitted model represented by a \code{brmsfit} object
#' 
#' Summarize estimated fixed and random effects as well as other useful
#' results included in a \code{brmsfit} object.
#'
#' @param object An object of class \code{brmsfit}
#' @param ... Other potential arguments
#' 
#' @author Paul-Christian Buerkner \email{paul.buerkner@@gmail.com}
#' 
#' @method summary brmsfit
#' @export
summary.brmsfit <- function(object, ...) {
  ee <- extract_effects(object$formula, family = object$family)
  out <- brmssummary(formula = update_formula(object$formula, partial = object$partial),
             family = object$family, link = object$link, data.name = object$data.name, 
             group = names(object$ranef), nobs = nobs(object), ngrps = brms::ngrps(object), 
             autocor = object$autocor)
  if (length(object$fit@sim)) {
    out$n.chains <- length(object$fit@sim$samples)
    out$n.iter = attr(object$fit@sim$samples[[1]],"args")$iter
    out$n.warmup = attr(object$fit@sim$samples[[1]],"args")$warmup
    out$n.thin = attr(object$fit@sim$samples[[1]],"args")$thin
    out$sampler = attr(object$fit@sim$samples[[1]],"args")$sampler_t
    if (length(ee$response) == 1) out$WAIC <- WAIC(object)$waic
    
    pars <- parnames(object)
    meta_pars <- object$fit@sim$pars_oi
    meta_pars <- meta_pars[!apply(sapply(paste0("^",c("r_","prior_")), 
                                  grepl, x = meta_pars, ...), 1, any)]
    fit_summary <- rstan::summary(object$fit, pars = meta_pars, probs = c(0.025, 0.975))
    col_names <- c("Estimate", "Est.Error", "l-95% CI", "u-95% CI", "Eff.Sample", "Rhat")
    
    fix_pars <- pars[grepl("^b_", pars)]
    out$fixed <- matrix(fit_summary$summary[fix_pars,-c(2)], ncol = 6)
    colnames(out$fixed) <- col_names
    rownames(out$fixed) <- gsub("^b_", "", fix_pars)
    
    spec_pars <- pars[pars %in% c("nu","shape","delta") | 
      apply(sapply(c("^sigma_", "^rescor_"), grepl, x = pars), 1, any)]
    out$spec_pars <- matrix(fit_summary$summary[spec_pars,-c(2)], ncol = 6)
    if (object$family %in% c("gaussian", "student", "cauchy")) {
      spec_pars[grepl("^sigma_", spec_pars)] <- paste0("sigma(",ee$response,")")
      spec_pars[grepl("^rescor_", spec_pars)] <- get_cornames(ee$response, type = "rescor")   
    }    
    colnames(out$spec_pars) <- col_names
    rownames(out$spec_pars) <- spec_pars
    
    cor_pars <- pars[grepl("^ar|^ma", pars)]
    out$cor_pars <- matrix(fit_summary$summary[cor_pars,-c(2)], ncol = 6)
    colnames(out$cor_pars) <- col_names
    rownames(out$cor_pars) <- cor_pars
    
    if (length(out$group)) {
      for (i in 1:length(out$group)) {
        rnames <- object$ranef[[i]]
        sd_pars <- paste0("sd_", out$group[i],"_",rnames)
        cor_pars <- intersect(get_cornames(rnames, type = paste0("cor_",out$group[i]),
                                           brackets = FALSE), parnames(object))
        sd_names <- paste0("sd(",rnames,")")
        cor_names <- get_cornames(rnames, subset = cor_pars, subtype = out$group[i])
        out$random[[out$group[i]]] <- matrix(fit_summary$summary[c(sd_pars, cor_pars),-c(2)], ncol = 6)
        colnames(out$random[[out$group[i]]]) <- col_names
        rownames(out$random[[out$group[i]]]) <- c(sd_names, cor_names)
      }
    }
  }  
  out
}

#' @export
nobs.brmsfit <- function(object, ...) length(object$data$Y)

#' @export
ngrps.brmsfit <- function(object, ...) {
  group <- unlist(extract_effects(object$formula, family = object$family)$group)
  if (length(group)) {
    out <- setNames(lapply(1:length(group), function(i) object$data[[paste0("N_",i)]]), group)
    out <- out[!duplicated(group)]
  } else out <- NULL
  out
}

#' @export
formula.brmsfit <- function(x, ...) x$formula

#' @export
launch_shiny.brmsfit <- function(x, rstudio = getOption("shinystan.rstudio"), ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  shinystan::launch_shinystan(x$fit, rstudio = rstudio, ...)
}

#' Trace and density plots for MCMC samples
#' 
#' @param x An object of class \code{brmsfit}.
#' @param parameters Name of the parameters to plot, as given by a character vector or a regular expression.
#'   By default, all parameters except for random effects, posterior predictives, and log likelihood values are plotted. 
#' @param N The number of parameters plotted per page.
#' @param ask logical; Indicates if the user is prompted before a new page is plotted.   
#' @param ... Additional arguments passed to function 'grid.arrange' of package 'gridExtra'.
#' 
#' @return NULL
#' 
#' @author Paul-Christian Buerkner \email{paul.buerkner@@gmail.com}
#' 
#' @examples
#' \dontrun{ 
#' fit_e <- brm(count ~ log_Age_c + log_Base4_c * Trt_c + (1|patient) + (1|visit), 
#'              data = epilepsy, family = "poisson")
#' ## plot fixed effects as well as standard devations of the random effects
#' plot(fit_e)
#' ## plot fixed effects only and combine the chains into one posterior
#' plot(fit_e, parameters = "^b_", combine = TRUE) 
#' }
#' 
#' @method plot brmsfit
#' @import ggplot2
#' @export
plot.brmsfit <- function(x, parameters = NA, N = 5, ask = TRUE, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (!is.wholenumber(N) || N < 1) 
    stop("N must be a positive integer")
  if (!is.character(parameters)) 
    parameters <- c("^b_", "^sd_", "^cor_", "^sigma", "^rescor", "^nu$", 
                    "^shape$", "^delta$", "^ar", "^ma")
  samples <- posterior.samples(x, parameters = parameters, add_chains = TRUE)
  pars <- names(samples)[which(!names(samples) %in% c("chains", "iter"))] 
  
  default.ask <- grDevices::devAskNewPage()
  grDevices::devAskNewPage(ask = FALSE)
  for (i in 1:ceiling(length(pars)/N)) {
    plots <- lapply(pars[((i-1)*N+1):min(i*N,length(pars))], td_plot, x = samples)
    gridExtra::grid.arrange(grobs = plots, nrow = length(plots), ncol = 1, ...)
    if (i == 1) grDevices::devAskNewPage(ask = ask)
  }
  grDevices::devAskNewPage(default.ask)
}

#' @export
linear_predictor.brmsfit <- function(x, newdata = NULL, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (is.null(newdata)) data <- x$data
  else if (is.data.frame(newdata))
    data <- amend_newdata(newdata, formula = x$formula, family = x$family, 
                           autocor = x$autocor, partial = x$partial) # can be found in data.R
  else stop("newdata must be a data.frame")
  n.samples <- nrow(posterior.samples(x, parameters = "^lp__$"))
  eta <- matrix(0, nrow = n.samples, ncol = data$N)
  X <- data$X
  if (!is.null(X) && ncol(X) && x$family != "categorical") {
    b <- posterior.samples(x, parameters = "^b_[^\\[]+$")
    eta <- eta + fixef_predictor(X = X, b = b)  
  }
  
  group <- names(x$ranef)
  all_groups <- extract_effects(x$formula)$group # may contain the same group more than ones
  if (length(group)) {
    for (i in 1:length(group)) {
      if (any(grepl(paste0("^lev_"), names(data)))) { # implies brms > 0.4.2
        # create a single RE design matrix for every grouping factor
        Z <- do.call(cbind, lapply(which(all_groups == group[i]), function(k) 
          get(paste0("Z_",k), data)))
        gf <- get(paste0("lev_",match(group[i], all_groups)), data)
      } else { # implies brms < 0.4.2
        Z <- get(paste0("Z_",group[i]), data)
        gf <- get(group[i], data)
      }
      r <- posterior.samples(x, parameters = paste0("^r_",group[i],"\\["))
      eta <- eta + ranef_predictor(Z = Z, gf = gf, r = r) 
    }
  }
  if (x$autocor$p > 0) {
    Yar <- as.matrix(data$Yar)
    ar <- posterior.samples(x, parameters = "^ar\\[")
    eta <- eta + fixef_predictor(X = Yar, b = ar)
  }
  if (x$autocor$q > 0) {
    ma <- posterior.samples(x, parameters = "^ma\\[")
    eta <- ma_predictor(data = data, ma = ma, eta = eta, link = x$link)
  }
  if (x$family %in% c("cumulative", "cratio", "sratio", "acat")) {
    Intercept <- posterior.samples(x, "^b_Intercept\\[")
    if (!is.null(data$Xp) && ncol(data$Xp)) {
      p <- posterior.samples(x, paste0("^b_",colnames(data$Xp),"\\["))
      etap <- partial_predictor(Xp = data$Xp, p = p, max_obs = data$max_obs)
    }  
    else etap <- array(0, dim = c(dim(eta), data$max_obs-1))
    for (k in 1:(data$max_obs-1)) {
      etap[,,k] <- etap[,,k] + eta
      if (x$family %in% c("cumulative", "sratio")) etap[,,k] <-  Intercept[,k] - etap[,,k]
      else etap[,,k] <- etap[,,k] - Intercept[,k]
    }
    eta <- etap
  }
  else if (x$family == "categorical") {
    if (!is.null(data$X)) {
      p <- posterior.samples(x, parameters = "^b_")
      etap <- partial_predictor(data$X, p, data$max_obs)
    }
    else etap <- array(0, dim = c(dim(eta), data$max_obs-1))
    for (k in 1:(data$max_obs-1)) etap[,,k] <- etap[,,k] + eta
    eta <- etap
  }
  eta
}


#' Extract Model Fitted Values of \code{brmsfit} Objects
#' 
#' @inheritParams residuals.brmsfit
#' 
#' @details Currently, the method does not support \code{categorical} or ordinal models. 
#'
#' @return Fitted values extracted from \code{object}. If \code{summary = TRUE} this is a S x N matrix and if \code{summary = FALSE}
#'   a N x C matrix, where S is the number of samples, N is the number of observations, 
#'   and C is equal to \code{length(probs) + 2}.  
#'
#' @examples 
#' \dontrun{
#' ## fit a model
#' fit <- brm(rating ~ treat + period + carry + (1|subject), data = inhaler,
#'            n.cluster = 2)
#' 
#' ## extract fitted values
#' fitted_values <- fitted(fit)
#' head(fitted_values)
#' }
#' 
#' @export 
fitted.brmsfit <- function(object, summary = TRUE, probs = c(0.025, 0.975), ...) {
  if (!is(object$fit, "stanfit") || !length(object$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (object$family %in% c("categorical", "cumulative", "sratio", "cratio", "acat"))
    stop(paste("fitted values not yet implemented for family", object$family))
  mu <- ilink(linear_predictor(object), object$link)
  if (summary) {
    mu <- do.call(cbind, lapply(c("mean", "sd", "quantile"), get_estimate, 
                                 samples = mu, probs = probs))
    colnames(mu) <- c("Estimate", "Est.Error", paste0(probs * 100, "%ile"))
  }
  mu
}

#' Extract Model Residuals from brmsfit Objects
#' 
#' @param object An object of class \code{brmsfit}
#' @param type The type of the residuals, either \code{ordinary} or \code{pearson}. Currently, the latter 
#'   is only supported for families \code{binomial} and \code{bernoulli}
#' @param summary logical. Should summary statistics (i.e. means, sds, and 95\% intervals) be returned
#'  instead of the raw values. Default is \code{FALSE}
#' @param probs The percentiles to be computed by the \code{quantile} function. Only used if \code{summary = TRUE}.
#' @param ... Currently ignored
#' 
#' @details Currently, the method does not support \code{categorical} or ordinal models. 
#' 
#' @return Models residuals. If \code{summary = TRUE} this is a S x N matrix and if \code{summary = FALSE}
#'   a N x C matrix, where S is the number of samples, N is the number of observations, 
#'   and C is equal to \code{length(probs) + 2}.  
#' 
#' @examples 
#' \dontrun{
#' ## fit a model
#' fit <- brm(rating ~ treat + period + carry + (1|subject), data = inhaler,
#'            n.cluster = 2)
#' 
#' ## extract residuals 
#' res <- residuals(fit, summary = TRUE)
#' head(res)
#' }
#' 
#' @export
residuals.brmsfit <- function(object, type = c("ordinary", "pearson"), summary = TRUE, 
                              probs = c(0.025, 0.975), ...) {
  type <- match.arg(type)
  if (!is(object$fit, "stanfit") || !length(object$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (object$family %in% c("categorical", "cumulative", "sratio", "cratio", "acat"))
    stop(paste("residuals not yet implemented for family", object$family))
  if (type == "pearson" && !object$family %in% c("binomial", "bernoulli"))
    stop("Pearson residuals are currently only available for families binomial and bernoulli")
  
  mu <- fitted(object)
  if (object$family %in% c("binomial", "bernoulli")) {
    if (object$family == "binomial")
      max_obs <- matrix(rep(object$data$max_obs, nrow(mu)), nrow = nrow(mu), byrow = TRUE)
    else max_obs <- 1
    mu <- mu * max_obs
  }
  Y <- matrix(rep(as.numeric(object$data$Y), nrow(mu)), nrow = nrow(mu), byrow = TRUE)
  res <- Y - mu
  colnames(res) <- NULL
  
  if (type == "pearson")
    res <- res / sqrt(mu * (max_obs - mu) / max_obs)  
  
  # for compatibility with the macf function (see correlations.R)
  # so that the colnames of the output correspond to the levels of the autocor grouping factor
  if (is(object$autocor, "cor_arma") && sum(object$autocor$p, object$autocor$q) > 0) {
    tgroup <- extract_time(object$autocor$formula)$group
    if (nchar(tgroup)) colnames(res) <- object$data[[tgroup]]
  }
  
  if (summary) {
    res <- do.call(cbind, lapply(c("mean", "sd", "quantile"), get_estimate, 
                                 samples = res, probs = probs))
    colnames(res) <- c("Estimate", "Est.Error", paste0(probs * 100, "%ile"))
  }
  res
}

#' Model Predictions of \code{brmsfit} Objects
#' 
#' Make predictions based on the fitted model parameters. 
#' Can be performed for the data used to fit the model (posterior predictive checks) or for new data.
#' 
#' @inheritParams residuals.brmsfit
#' @param newdata An optional data.frame containing new data to make predictions for.
#'   If \code{NULL} (the default), the data used to fit the model is applied.
#' @param transform A function or a character string naming a function to be applied on the predicted responses
#'   before summary statistics are computed.
#' 
#' @return predicted values of the response variable. If \code{summary = TRUE} this is a S x N matrix and if \code{summary = FALSE}
#'   a N x C matrix, where S is the number of samples, N is the number of observations, 
#'   and C is equal to \code{length(probs) + 2}.   
#' 
#' @details Be careful when using newdata with factors: The predicted results are only valid
#'   if all factor levels present in the initial data are also defined and ordered correctly 
#'   for the factors in newdata. 
#' 
#' @examples 
#' \dontrun{
#' ## fit a model
#' fit <- brm(time | cens(censored) ~ age + sex, data = kidney,
#'            family = "exponential", silent = TRUE)
#' 
#' ## posterior predictive checks
#' pp <- predict(fit)
#' head(pp)
#' 
#' ## predict response for new data (be careful with factors)
#' newdata <- data.frame(age = c(20,50), 
#'                        sex = factor(c("male", "female"), levels = c("male", "female")))
#' predict(fit, newdata = newdata)
#' }
#' 
#' @export 
predict.brmsfit <- function(object, newdata = NULL, transform = NULL, 
                            summary = TRUE, probs = c(0.025, 0.975), ...) {
  if (!is(object$fit, "stanfit") || !length(object$fit@sim)) 
    stop("The model does not contain posterior samples")
  family <- object$family
  ee <- extract_effects(object$formula, family = family)
  if (object$link == "log" && family == "gaussian" && length(ee$response) == 1) 
    family <- "lognormal"
  else if (family == "gaussian" && length(ee$response) > 1)
    family <- "multinormal"
  
  # compute all necessary samples
  samples <- list(eta = linear_predictor(object, newdata = newdata))
  if (family %in% c("gaussian", "student", "cauchy", "lognormal", "multinormal") && !is.formula(ee$se))
    samples$sigma <- as.matrix(posterior_samples(object, parameters = "^sigma_"))
  if (family == "student") 
    samples$nu <- as.matrix(posterior_samples(object, parameters = "^nu$"))
  if (family %in% c("gamma", "weibull","negbinomial")) 
    samples$shape <- as.matrix(posterior_samples(object, parameters = "^shape$"))
  if (family == "multinormal") {
    samples$rescor <- as.matrix(posterior_samples(object, parameters = "^rescor_"))
    samples$Sigma <- get_cov_matrix(sd = samples$sigma, cor = samples$rescor)$cov
    message(paste("Computing posterior predictive samples of multinormal distribution. \n", 
                  "This may take a while."))
  }
  
  # use newdata if defined
  if (is.null(newdata)) data <- object$data
  else data <- amend_newdata(newdata, formula = object$formula, family = object$family, 
                              autocor = object$autocor, partial = object$partial) # can be found in data.R
  
  #call predict functions
  predict_fun <- get(paste0("predict_",family))
  out <- do.call(cbind, lapply(1:ncol(samples$eta), function(n) 
    do.call(predict_fun, list(n = n, data = data, samples = samples, link = object$link))))
  if (!is.null(transform)) 
    out <- do.call(transform, list(out))
  if (summary) {
    out <- do.call(cbind, lapply(c("mean", "sd", "quantile"), get_estimate, 
                                 samples = out, probs = probs))
    colnames(out) <- c("Estimate", "Est.Error", paste0(probs * 100, "%ile"))
  }
  
  #sort predicted responses in case of multinormal models
  if (family == "multinormal") {
    nobs <- object$data$N_trait * object$data$K_trait
    to_order <- unlist(lapply(1:object$data$K_trait, function(k) seq(k, nobs, object$data$K_trait)))
    if (summary) out <- out[to_order, ] # observations in rows
    else out <- out[, to_order] # observations in columns
  }
  out
}

#' @export
WAIC.brmsfit <- function(x, ..., compare = TRUE) {
  models <- list(x, ...)
  names <- c(deparse(substitute(x)), sapply(substitute(list(...))[-1], deparse))
  if (length(models) > 1) {
    out <- setNames(lapply(models, calculate_ic, ic = "waic"), names)
    class(out) <- c("iclist", "list")
    if (compare) attr(out, "compare") <- compare_ic(out, ic = "waic")
  }  
  else out <- calculate_ic(x, ic = "waic")
  out
}

#' @export
LOO.brmsfit <- function(x, ..., compare = TRUE) {
  models <- list(x, ...)
  names <- c(deparse(substitute(x)), sapply(substitute(list(...))[-1], deparse))
  if (length(models) > 1) {
    out <- setNames(lapply(models, calculate_ic, ic = "loo"), names)
    class(out) <- c("iclist", "list")
    if (compare) attr(out, "compare") <- compare_ic(out, ic = "loo")
  }  
  else out <- calculate_ic(x, ic = "loo")
  out
}

#' @export
loglik.brmsfit <- function(x, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  ee <- extract_effects(x$formula, family = x$family)
  if (x$link == "log" && x$family == "gaussian" && length(ee$response) == 1) 
    x$family <- "lognormal"
  if (x$family == "gaussian" && length(ee$response) > 1)
    x$family <- "multinormal"
  
  samples <- list(eta = linear_predictor(x))
  if (x$family %in% c("gaussian", "student", "cauchy", "lognormal", "multinormal") && !is.formula(ee$se)) 
    samples$sigma <- as.matrix(posterior.samples(x, parameters = "^sigma_"))
  if (x$family == "student") 
    samples$nu <- as.matrix(posterior.samples(x, parameters = "^nu$"))
  if (x$family %in% c("gamma", "weibull","negbinomial")) 
    samples$shape <- as.matrix(posterior.samples(x, parameters = "^shape$"))
  if (x$family == "multinormal") {
    samples$rescor <- as.matrix(posterior.samples(x, parameters = "^rescor_"))
    samples$Sigma <- get_cov_matrix(sd = samples$sigma, cor = samples$rescor)$cov
    message(paste("Computing pointwise log-likelihood of multinormal distribution. \n",
                  "This may take a while."))
  }
  loglik_fun <- get(paste0("loglik_",x$family))
  return(do.call(cbind, lapply(1:nrow(as.matrix(x$data$Y)), function(n) 
    do.call(loglik_fun, list(n = n, data = x$data, samples = samples, link = x$link)))))
}

#' @export
hypothesis.brmsfit <- function(x, hypothesis, class = "b", alpha = 0.05, ...) {
  if (!is(x$fit, "stanfit") || !length(x$fit@sim)) 
    stop("The model does not contain posterior samples")
  if (!is.character(hypothesis)) 
    stop("Argument hypothesis must be a character vector")
  if (alpha < 0 || alpha > 1)
    stop("Argument alpha must be in [0,1]")
  if (!is.null(class) && nchar(class)) class <- paste0(class,"_")
  else class <- ""
  pars <- rename(parnames(x)[grepl("^",class, parnames(x))],
                 symbols = ":", subs = "__")
  
  out <- do.call(rbind, lapply(hypothesis, function(h) {
    h <- rename(h, symbols = c(" ", ":"), subs = c("", "__"))
    sign <- unlist(regmatches(h, gregexpr("=|<|>", h)))
    lr <- unlist(regmatches(h, gregexpr("[^=<>]+", h)))
    if (length(sign) != 1 || length(lr) != 2)
      stop("Every hypothesis must be of the form 'left (= OR < OR >) right'")
    h <- paste0(lr[1], ifelse(lr[2] != "0", paste0("-(",lr[2],")"), ""))
    varsH <- unique(find_names(h))
    parsH <- paste0(class, varsH)
    if (!all(parsH %in% pars)) 
      stop(paste("The following parameters cannot be found in the model:", 
                 paste0(gsub("__", ":", parsH[which(!parsH %in% pars)]), collapse = ", ")))
    
    # prepare for renaming of parameters so that h can be evaluated
    parsH <- rename(parsH, "__", ":")
    h_renamed <- rename(h, c("[", "]"), c(".", "."))
    symbols <- c(paste0("^",class), ":", "\\[", "\\]")
    subs <- c("", "__", ".", ".")
    
    # get posterior samples
    samples <- posterior_samples(x, parameters = parsH, exact_match = TRUE)
    names(samples) <- rename(names(samples), symbols = symbols, subs = subs, fixed = FALSE)
    samples <- matrix(with(samples, eval(parse(text = h_renamed))), ncol=1)
    
    # get prior samples
    prior_samples <- prior_samples(x, parameters = parsH, fixed = TRUE)
    if (!is.null(prior_samples) && ncol(prior_samples) == length(varsH)) {
      names(prior_samples) <- rename(names(prior_samples), symbols = symbols, subs = subs, fixed = FALSE)
      prior_samples <- matrix(with(prior_samples, eval(parse(text = h_renamed))), ncol=1)
    } else prior_samples <- NULL

    #evaluate hypothesis
    wsign <- ifelse(sign == "=", "equal", ifelse(sign == "<", "less", "greater"))
    probs <- switch(wsign, equal = c(alpha/2, 1-alpha/2), less = c(0, 1-alpha), greater = c(alpha, 1))
    out <- as.data.frame(matrix(unlist(lapply(c("mean", "sd", "quantile", "evidence_ratio"), get_estimate, 
      samples = samples, probs = probs, wsign = wsign, prior_samples = prior_samples, ...)), nrow = 1))
    if (sign == "<") out[1,3] <- -Inf
    else if (sign == ">") out[1,4] <- Inf
    out <- cbind(out, ifelse(!(out[1,3] <= 0 && 0 <= out[1,4]), '*', ''))
    rownames(out) <- paste(rename(h, "__", ":"), sign, "0")
    cl <- (1-alpha)*100
    colnames(out) <- c("Estimate", "Est.Error", paste0("l-",cl,"% CI"), paste0("u-",cl,"% CI"), "Evid.Ratio", "")
    out
  }))
  out <- list(hypothesis = out, class = substr(class, 1, nchar(class)-1), alpha = alpha)
  class(out) <- "brmshypothesis"
  out
}