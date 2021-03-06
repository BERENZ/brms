melt <- function(data, response, family) {
  # melt data frame for multinormal models
  #
  # Args:
  #   data: a data.frame
  #   response: names of the response variables
  #   family: the model family
  #
  # Returns:
  #   data in long format 
  is_hurdle <- indicate_hurdle(family)
  is_zero_inflated <- indicate_zero_inflated(family)
  nresp <- length(response)
  if (nresp > 1 && family == "gaussian" || 
      nresp == 2 && (is_hurdle || is_zero_inflated)) {
    if (!is(data, "data.frame"))
      stop("data must be a data.frame for multivarite models")
    if ("trait" %in% names(data))
      stop("trait is a resevered variable name in multivariate models")
    if (is_hurdle || is_zero_inflated) {
      if (response[2] %in% names(data))
        stop(paste(response[2], "is a resevered variable name"))
      # dummy variable not actually used in Stan
      data[response[2]] <- rep(0, nrow(data))
    }
    new_columns <- data.frame(unlist(lapply(response, rep, time = nrow(data))), 
                              as.numeric(as.matrix(data[, response])))
    names(new_columns) <- c("trait", response[1])
    old_columns <- data[, which(!names(data) %in% response), drop = FALSE]
    old_columns <- do.call(rbind, lapply(response, function(i) old_columns))
    data <- cbind(old_columns, new_columns)
  } else if (nresp > 1) {
    stop("Invalid multivariate model")
  }
  data
}  

combine_groups <- function(data, ...) {
  # combine grouping factors
  #
  # Args:
  #   data: a data.frame
  #   ...: the grouping factors to be combined. 
  #
  # Returns:
  #   a data.frame containing all old variables and the new combined grouping factors
  group <- c(...)
  if (length(group)) {
    for (i in 1:length(group)) {
      sgroup <- unlist(strsplit(group[[i]], ":"))
      if (length(sgroup) > 1) {
        new.var <- get(sgroup[1], data)
        for (j in 2:length(sgroup)) {
          new.var <- paste0(new.var, "_", get(sgroup[j], data))
        }
        data[[group[[i]]]] <- new.var
      }
    } 
  }
  data
}

update_data <- function(data, family, effects, ...,
                        drop.unused.levels = TRUE) {
  # update data for use in brm
  #
  # Args:
  #   data: the original data.frame
  #   family: the model family
  #   effects: output of extract_effects (see validate.R)
  #   ...: More formulae passed to combine_groups
  #        Currently only used for autocorrelation structures
  #   drop.unused.levels: logical; indicates whether unused factor levels
  #                       should be dropped
  #
  # Returns:
  #   model.frame in long format with combined grouping variables if present
  if (!"brms.frame" %in% class(data)) {
    data <- melt(data, response = effects$response, family = family)
    data <- stats::model.frame(effects$all, data = data, 
                               drop.unused.levels = drop.unused.levels)
    if (any(grepl("__", colnames(data))))
      stop("Variable names may not contain double underscores '__'")
    data <- combine_groups(data, effects$group, ...)
    class(data) <- c("brms.frame", "data.frame") 
  }
  data
}

#' Extract required data for \code{brms} models
#'
#' @inheritParams brm
#' @param ... Other arguments for internal usage only
#' 
#' @aliases brm.data
#' 
#' @return A named list of objects containing the required data to fit a \code{brms} model 
#' 
#' @author Paul-Christian Buerkner \email{paul.buerkner@@gmail.com}
#' 
#' @examples
#' data1 <- brmdata(rating ~ treat + period + carry + (1|subject), 
#'                  data = inhaler, family = "cumulative")
#' names(data1)
#' 
#' data2 <- brmdata(count ~ log_Age_c + log_Base4_c * Trt_c + (1|patient) + (1|visit), 
#'                  data = epilepsy, family = "poisson")
#' names(data2)
#'          
#' @export
brmdata <- function(formula, data = NULL, family = "gaussian", autocor = NULL, 
                    partial = NULL, cov.ranef = NULL, ...) {
  # internal arguments:
  #   newdata: logical; indicating if brmdata is called with new data
  #   keep_intercept: logical; indicating if the Intercept column
  #                   should be kept in the FE design matrix
  dots <- list(...)
  family <- check_family(family)$family
  is_linear <- indicate_linear(family)
  is_ordinal <- indicate_ordinal(family)
  is_count <- indicate_count(family)
  if (is.null(autocor)) autocor <- cor_arma()
  if (!is(autocor,"cor_brms")) stop("cor must be of class cor_brms")
  
  et <- extract_time(autocor$formula)
  ee <- extract_effects(formula = formula, family = family, partial, et$all)
  data <- update_data(data, family = family, effects = ee, et$group,
                      drop.unused.levels = !isTRUE(dots$newdata))
  
  # sort data in case of autocorrelation models
  if (sum(autocor$p, autocor$q) > 0) {
    if (family == "gaussian" && length(ee$response) > 1) {
      if (!grepl("^trait$|:trait$|^trait:|:trait:", et$group)) {
        stop(paste("autocorrelation structures for multiple responses must",
                   "contain 'trait' as grouping variable"))
      } else {
        to_order <- rmNULL(list(data[["trait"]], data[[et$group]], data[[et$time]]))
      }
    } else {
      to_order <- rmNULL(list(data[[et$group]], data[[et$time]]))
    }
    if (length(to_order)) 
      data <- data[do.call(order, to_order), ]
  }
  
  # response variable
  standata <- list(N = nrow(data), Y = unname(model.response(data)))
  if (!is.numeric(standata$Y) && !(is_ordinal || family %in% c("bernoulli", "categorical"))) 
    stop(paste("family", family, "expects numeric response variable"))
  
  # transform and check response variable for different families
  if (is_count || family == "binomial") {
    if (!all(is.wholenumber(standata$Y)) || min(standata$Y) < 0)
      stop(paste("family", family, "expects response variable of non-negative integers"))
  } else if (family == "bernoulli") {
    standata$Y <- as.numeric(as.factor(standata$Y)) - 1
    if (any(!standata$Y %in% c(0,1)))
      stop("family bernoulli expects response variable to contain only two different values")
  } else if (family == "categorical") { 
    standata$Y <- as.numeric(as.factor(standata$Y))
  } else if (is_ordinal) {
    if (is.factor(standata$Y)) {
      if (is.ordered(standata$Y)) standata$Y <- as.numeric(standata$Y)
      else stop(paste("family", family, "requires factored response variables to be ordered"))
    } else if (all(is.wholenumber(standata$Y))) {
      standata$Y <- standata$Y - min(standata$Y) + 1
    } else {
      stop(paste("family", family, "expects either integers or",
                 "ordered factors as response variables"))
    }
  } else if (indicate_skewed(family)) {
    if (min(standata$Y) < 0)
      stop(paste("family", family, "requires response variable to be non-negative"))
  } else if (family == "gaussian" && length(ee$response) > 1) {
    standata$Y <- matrix(standata$Y, ncol = length(ee$response))
    standata <- c(standata, list(N_trait = nrow(standata$Y), 
                                 K_trait = ncol(standata$Y)),
                                 NC_trait = ncol(standata$Y) * 
                                            (ncol(standata$Y) - 1) / 2) 
  } else if (indicate_hurdle(family) || indicate_zero_inflated(family)) {
    # the second half of Y is not used because it is only dummy data
    # that was put into data to make melt work correctly
    standata$Y <- standata$Y[1:(nrow(data) / 2)] 
    standata$N_trait <- length(standata$Y)
  }
  
  # fixed effects data
  rm_Intercept <- is_ordinal || !isTRUE(dots$keep_intercept)
  X <- get_model_matrix(ee$fixed, data, rm_intercept = rm_Intercept)
  if (family == "categorical") {
    standata <- c(standata, list(Kp = ncol(X), Xp = X))
  } else {
    standata <- c(standata, list(K = ncol(X), X = X))
  } 
  
  # random effects data
  if (length(ee$random)) {
    Z <- lapply(ee$random, get_model_matrix, data = data)
    r <- lapply(Z, colnames)
    ncolZ <- lapply(Z, ncol)
    expr <- expression(as.numeric(as.factor(get(g, data))),  # numeric levels passed to Stan
                       length(unique(get(g, data))),  # number of levels
                       ncolZ[[i]],  # number of random effects
                       Z[[i]],  # random effects design matrix
                       ncolZ[[i]] * (ncolZ[[i]]-1) / 2)  #  number of correlations
    if (isTRUE(dots$newdata)) {
      # for newdata only as levels are already defined correctly in amend_newdata
      expr[1] <- expression(get(g, data)) 
    }
    for (i in 1:length(ee$group)) {
      g <- ee$group[[i]]
      name <- paste0(c("J_", "N_", "K_", "Z_", "NC_"), i)
      if (ncolZ[[i]] == 1) 
        Z[[i]] <- as.vector(Z[[i]])
      for (j in 1:length(name)) {
        standata <- c(standata, setNames(list(eval(expr[j])), name[j]))
      }
      if (g %in% names(cov.ranef)) {
        cov_mat <- as.matrix(cov.ranef[[g]])
        found_level_names <- rownames(cov_mat)
        colnames(cov_mat) <- found_level_names
        true_level_names <- sort(as.character(unique(data[[g]])))
        if (is.null(found_level_names)) 
          stop(paste("Row names are required for covariance matrix of",g))
        if (nrow(cov_mat) != length(true_level_names))
          stop(paste("Dimension of covariance matrix of",g,"is incorrect"))
        if (any(sort(found_level_names) != true_level_names))
          stop(paste("Row names of covariance matrix of",g,"do not match names of the grouping levels"))
        if (!isSymmetric(unname(cov_mat)))
          stop(paste("Covariance matrix of grouping factor",g,"is not symmetric"))
        if (min(eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values) <= 0)
          warning(paste("Covariance matrix of grouping factor",g,"may not be positive definite"))
        cov_mat <- cov_mat[order(found_level_names), order(found_level_names)]
        if (length(r[[i]]) == 1) {
          cov_mat <- suppressWarnings(chol(cov_mat, pivot = TRUE))
          cov_mat <- t(cov_mat[, order(attr(cov_mat, "pivot"))])
        } else if (length(r[[i]]) > 1 && !ee$cor[[i]]) {
          cov_mat <- t(suppressWarnings(chol(kronecker(cov_mat, diag(ncolZ[[i]])), pivot = TRUE)))
        }
        standata <- c(standata, setNames(list(cov_mat), paste0("cov_",i)))
      }
    }
  }
  
  # addition and partial variables
  if (is.formula(ee$se)) {
    standata <- c(standata, list(sigma = .addition(formula = ee$se, data = data)))
  }
  if (is.formula(ee$weights)) {
    standata <- c(standata, list(weights = .addition(formula = ee$weights, data = data)))
    if (family == "gaussian" && length(ee$response) > 1) 
      standata$weights <- standata$weights[1:standata$N_trait]
  }
  if (is.formula(ee$cens)) {
    standata <- c(standata, list(cens = .addition(formula = ee$cens, data = data)))
  }
  if (is.formula(ee$trunc)) {
    standata <- c(standata, .addition(formula = ee$trunc))
    if (min(standata$Y) < standata$lb || max(standata$Y) > standata$ub) {
      stop("some responses are outside of the truncation boundaries")
    }
  }
  if (family == "inverse.gaussian") {
    # save as data to reduce computation time in Stan
    if (is.formula(ee[c("weights", "cens")])) {
      standata$log_Y <- log(standata$Y) 
    } else {
      standata$log_Y <- sum(log(standata$Y))
    }
    standata$sqrt_Y <- sqrt(standata$Y)
  }
  if (family == "binomial") {
    standata$trials <- if (!length(ee$trials)) max(standata$Y)
                        else if (is.wholenumber(ee$trials)) ee$trials
                        else if (is.formula(ee$trials)) .addition(formula = ee$trials, data = data)
                        else stop("Response part of formula is invalid.")
    standata$max_obs <- standata$trials  # for backwards compatibility
    if (max(standata$trials) == 1) 
      message("Only 2 levels detected so that family 'bernoulli' might be a more efficient choice.")
    if (any(standata$Y > standata$trials))
      stop("Number of trials is smaller than the response variable would suggest.")
  }
  if (is_ordinal || family == "categorical") {
    standata$ncat <- if (!length(ee$cat)) max(standata$Y)
                        else if (is.wholenumber(ee$cat)) ee$cat
                        else if (is.formula(ee$cat)) {
                          warning("observations may no longer have different numbers of categories.")
                          max(.addition(formula = ee$cat, data = data))
                        }
                        else stop("Response part of formula is invalid.")
    standata$max_obs <- standata$ncat  # for backwards compatibility
    if (max(standata$ncat) == 2) 
      message("Only 2 levels detected so that family 'bernoulli' might be a more efficient choice.")
    if (any(standata$Y > standata$ncat))
      stop("Number of categories is smaller than the response variable would suggest.")
  }  
  
  # get data for partial effects
  if (is.formula(partial)) {
    if (family %in% c("sratio","cratio","acat")) {
      Xp <- get_model_matrix(partial, data, rm_intercept = TRUE)
      standata <- c(standata, list(Kp = ncol(Xp), Xp = Xp))
      fp <- intersect(colnames(X), colnames(Xp))
      if (length(fp))
        stop(paste("Variables cannot be modeled as fixed and partial effects at the same time.",
                   "Error occured for variables:", paste(fp, collapse = ", ")))
    } else {
      stop("partial effects are only meaningful for families 'sratio', 'cratio', and 'acat'")  
    }
  }
  
  # autocorrelation variables
  if (is(autocor,"cor_arma") && autocor$p + autocor$q > 0) {
    tgroup <- data[[et$group]]
    if (is.null(tgroup)) 
      tgroup <- rep(1, standata$N) 
    if (autocor$p > 0) {
      standata$Yar <- ar_design_matrix(Y = standata$Y, p = autocor$p, group = tgroup)
      standata$Kar <- autocor$p
    }
    if (autocor$q > 0 && is(autocor,"cor_arma")) {
      standata$Ema_pre <- matrix(0, nrow = standata$N, ncol = autocor$q)
      standata$Kma <- autocor$q
      standata$tgroup <- as.numeric(as.factor(tgroup))
    }
  } 
  standata
}  

#' @export
brm.data <- function(formula, data = NULL, family = "gaussian", autocor = NULL, 
                     partial = NULL, cov.ranef = NULL)  {
  # deprectated alias of brmdata
  brmdata(formula = formula, data = data, family = family, autocor = autocor,
          partial = partial, cov.ranef = cov.ranef)
}

get_model_matrix <- function(formula, data = environment(formula), rm_intercept = FALSE) {
  # Construct Design Matrices for \code{brms} models
  # 
  # Args:
  #   formula: An object of class "formula"
  #   data: A data frame created with \code{model.frame}. If another sort of object, 
  #         \code{model.frame} is called first.
  #   rm_intercept: Flag indicating if the intercept column should be removed from the model.matrix. 
  #                 Primarily useful for ordinal models.
  # 
  # Returns:
  #   The design matrix for a regression-like model with the specified formula and data. 
  #   For details see the documentation of \code{model.matrix}.
  if (!is(formula, "formula")) return(NULL) 
  X <- stats::model.matrix(formula, data)
  new_colnames <- rename(colnames(X), check_dup = TRUE)
  if (rm_intercept && "Intercept" %in% new_colnames) {
    X <- as.matrix(X[, -(1)])
    if (ncol(X)) colnames(X) <- new_colnames[2:length(new_colnames)]
  } 
  else colnames(X) <- new_colnames
  X   
}

ar_design_matrix <- function(Y, p, group)  { 
  # calculate design matrix for autoregressive effects
  #
  # Args:
  #   Y: a vector containing the response variable
  #   p: autocor$p
  #   group: vector containing the grouping variable for each observation
  #
  # Notes: 
  #   expects Y to be sorted after group already
  # 
  # Returns:
  #   the deisgn matrix for autoregressive effects
  if (length(Y) != length(group)) 
    stop("Y and group must have the same length")
  if (p > 0) {
    U_group <- unique(group)
    N_group <- length(U_group)
    out <- matrix(0, nrow = length(Y), ncol = p)
    ptsum <- rep(0, N_group + 1)
    for (j in 1:N_group) {
      ptsum[j+1] <- ptsum[j] + sum(group == U_group[j])
      for (i in 1:p) {
        if (ptsum[j]+i+1 <= ptsum[j+1])
          out[(ptsum[j]+i+1):ptsum[j+1], i] <- Y[(ptsum[j]+1):(ptsum[j+1]-i)]
      }
    }
  }
  else out <- NULL
  out
}

.addition <- function(formula, data = NULL) {
  # computes data for addition arguments
  if (!is.formula(formula))
    formula <- as.formula(formula)
  eval(formula[[2]], data, environment(formula))
}

.se <- function(x) {
  # standard errors for meta-analysis
  if (min(x) < 0) stop("standard errors must be non-negative")
  x  
}

.weights <- function(x) {
  # weights to be applied on any model
  if (min(x) < 0) stop("weights must be non-negative")
  x
}

.trials <- function(x) {
  # trials for binomial models
  if (any(!is.wholenumber(x) || x < 1))
    stop("number of trials must be positive integers")
  x
}

.cat <- function(x) {
  # number of categories for categorical and ordinal models
  if (any(!is.wholenumber(x) || x < 1))
    stop("number of categories must be positive integers")
  x
}

.cens <- function(x) {
  # indicator for censoring
  if (is.factor(x)) x <- as.character(x)
  cens <- unname(sapply(x, function(x) {
    if (grepl(paste0("^",x), "right") || is.logical(x) && isTRUE(x)) x <- 1
    else if (grepl(paste0("^",x), "none") || is.logical(x) && !isTRUE(x)) x <- 0
    else if (grepl(paste0("^",x), "left")) x <- -1
    else x
  }))
  if (!all(unique(cens) %in% c(-1:1)))
    stop (paste0("Invalid censoring data. Accepted values are 'left', 'none', and 'right' \n",
                 "(abbreviations are allowed) or -1, 0, and 1. TRUE and FALSE are also accepted \n",
                 "and refer to 'right' and 'none' respectively."))
  cens
}

.trunc <- function(lb = -Inf, ub = Inf) {
  lb <- as.numeric(lb)
  ub <- as.numeric(ub)
  if (length(lb) != 1 || length(ub) != 1) {
    stop("Invalid truncation values")
  }
  list(lb = lb, ub = ub)
}
  