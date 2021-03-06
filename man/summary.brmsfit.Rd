% Generated by roxygen2 (4.1.1): do not edit by hand
% Please edit documentation in R/brmsfit-methods.R
\name{summary.brmsfit}
\alias{summary.brmsfit}
\title{Create a summary of a fitted model represented by a \code{brmsfit} object}
\usage{
\method{summary}{brmsfit}(object, waic = TRUE, ...)
}
\arguments{
\item{object}{An object of class \code{brmsfit}}

\item{waic}{logical; indicating if the WAIC should be computed
(this will take some time for larger models)}

\item{...}{Other potential arguments}
}
\description{
Summarize estimated fixed and random effects as well as other useful
results included in a \code{brmsfit} object.
}
\author{
Paul-Christian Buerkner \email{paul.buerkner@gmail.com}
}

