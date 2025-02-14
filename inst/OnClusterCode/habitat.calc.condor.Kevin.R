## This runs on the condor node to do all habitat calcs

install.packages("ncdf4_1.4.zip", lib='./rLibs', repos=NULL)
install.packages("rGLM_0.1.5.tar.gz", lib='./rLibs', repos=NULL, type='source')
install.packages('rLakeAnalyzer_1.3.3.tar.gz', lib='./rLibs', repos=NULL, type='source')
install.packages('stringr_0.6.2.zip', lib='./rLibs', repos=NULL)

source('chained.habitat.out.R')
source('GLM.physics.R')

library('ncdf4')
library('rGLM')
library('rLakeAnalyzer')
library('stringr')

info = read.table('run.info.tsv', header=TRUE, sep='\t')

chained.habitat.calc.kevin('.', 'kevin.metrics.out.tsv', info$WBIC)