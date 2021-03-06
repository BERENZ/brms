% Generated by roxygen2 (4.1.1): do not edit by hand
% Please edit documentation in R/brmsfit-methods.R
\name{residuals.brmsfit}
\alias{residuals.brmsfit}
\title{Extract Model Residuals from brmsfit Objects}
\usage{
\method{residuals}{brmsfit}(object, re_formula = NULL, type = c("ordinary",
  "pearson"), summary = TRUE, probs = c(0.025, 0.975), ...)
}
\arguments{
\item{object}{An object of class \code{brmsfit}}

\item{re_formula}{formula containing random effects to be considered in the prediction.
If \code{NULL} (default), include all random effects; if \code{NA}, include no random effects.
Other options will be implemented in the future.}

\item{type}{The type of the residuals, either \code{"ordinary"} or \code{"pearson"}.
  More information is provided under 'Details'.}

\item{summary}{logical. Should summary statistics (i.e. means, sds, and 95\% intervals) be returned
instead of the raw values. Default is \code{TRUE}}

\item{probs}{The percentiles to be computed by the \code{quantile} function.
Only used if \code{summary} is \code{TRUE}.}

\item{...}{Currently ignored}
}
\value{
Model residuals. If \code{summary = TRUE} this is a N x C matrix
  and if \code{summary = FALSE} a S x N matrix, where S is the number of samples,
  N is the number of observations, and C is equal to \code{length(probs) + 2}.
}
\description{
Extract Model Residuals from brmsfit Objects
}
\details{
Residuals of type \code{ordinary} are of the form \eqn{R = Y - Yp},
  where \eqn{Y} is the observed and \eqn{Yp} is the predicted response.
  Residuals of type \code{pearson} are of the form \eqn{R = (Y - Yp) / Var(Y)},
  where \eqn{Var(Y)} is an estimation of the variance of \eqn{Y}. \cr

  Currently, \code{residuals.brmsfit} does not support \code{categorical} or ordinal models.
}
\examples{
\dontrun{
## fit a model
fit <- brm(rating ~ treat + period + carry + (1|subject), data = inhaler,
           n.cluster = 2)

## extract residuals
res <- residuals(fit, summary = TRUE)
head(res)
}
}

