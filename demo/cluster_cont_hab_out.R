## Lets cluserify things

local_url = paste0((Sys.info()["nodename"]),':4040')
driver_url = paste0('http://', (Sys.info()["nodename"]),':4041/')

library(parallel)

#lets try 50 to start
c1 = makePSOCKcluster(paste0('licon', 1:60), manual=TRUE, port=4044)

clusterExport(c1, varlist = 'local_url')
clusterExport(c1, varlist = 'driver_url')

#clusterCall(c1, function(){install.packages('devtools', repos='http://cran.rstudio.com')})
clusterCall(c1, function(){install.packages('rLakeAnalyzer', repos='http://cran.rstudio.com')})
clusterCall(c1, function(){install.packages('dplyr', repos='http://cran.rstudio.com')})
clusterCall(c1, function(){install.packages('lubridate', repos='http://cran.rstudio.com')})

clusterCall(c1, function(){library(devtools)})

#start http-server (npm install http-server -g) on a suitable port
#glmr_install     = clusterCall(c1, function(){install.packages('glmtools', repos=c('http://owi.usgs.gov/R', 'http://cran.rstudio.com'))})
glmr_install     = clusterCall(c1, function(){install_url(paste0('http://', local_url,'/GLMr_3.1.10.tar.gz'))})
glmtools_install = clusterCall(c1, function(){install_url(paste0('http://', local_url,'/glmtools_0.13.0.tar.gz'))})
lakeattr_install = clusterCall(c1, function(){install_url(paste0('http://', local_url,'/lakeattributes_0.8.7.tar.gz'))})
mdalakes_install = clusterCall(c1, function(){install_url(paste0('http://', local_url,'/mda.lakes_4.1.2.tar.gz'))})

library(lakeattributes)
library(mda.lakes)
library(dplyr)
library(glmtools)
source('demo/common_running_functions.R')

Sys.setenv(TZ='GMT')


future_hab_wtr = function(site_id, modern_era=1979:2012, future_era, driver_function=get_driver_path, secchi_function=function(site_id){}, nml_args=list()){
  
  library(lakeattributes)
  library(mda.lakes)
  library(dplyr)
  library(glmtools)
  
  fastdir = tempdir()
  if(file.exists('/mnt/ramdisk')){
    fastdir = '/mnt/ramdisk'
  }
  
  
  tryCatch({
    
    
    run_dir = file.path(fastdir, paste0(site_id, '_', sample.int(1e9, size=1)))
    cat(run_dir, '\n')
    dir.create(run_dir)
    
    #rename for dplyr
    nhd_id = site_id
    
    #get driver data
    driver_path = driver_function(site_id)
    driver_path = gsub('\\\\', '/', driver_path)
    
    
    #kds = get_kd_best(site_id, years=years, datasource = datasource)
    
    kd_avg = secchi_function(site_id) #secchi_conv/mean(kds$secchi_avg, na.rm=TRUE)
    
    #run with different driver and ice sources
    
    prep_run_glm_kd(site_id=site_id, 
                    path=run_dir, 
                    years=modern_era,
                    kd=kd_avg, 
                    nml_args=c(list(
                      dt=3600, subdaily=FALSE, nsave=24, 
                      timezone=-6,
                      csv_point_nlevs=0, 
                      snow_albedo_factor=1.1, 
                      meteo_fl=driver_path, 
                      cd=getCD(site_id, method='Hondzo')), 
                      nml_args))
    
    
    ##parse the habitat and WTR info. next run will clobber output.nc
    wtr_all = get_temp(file.path(run_dir, 'output.nc'), reference='surface')
    ## drop the first n burn-in years
    #years = as.POSIXlt(wtr$DateTime)$year + 1900
    #to_keep = !(years <= min(years) + nburn - 1)
    #wtr_all = wtr[to_keep, ]
    
    core_metrics = necsc_thermal_metrics_core(run_dir, site_id)
    
    hansen_habitat = hansen_habitat_calc(run_dir, site_id)
    
    #Run future era only if requested
    if(!missing(future_era)){
      kd_avg = secchi_function(site_id) #secchi_conv/mean(kds$secchi_avg, na.rm=TRUE)
      
      prep_run_glm_kd(site_id=site_id, 
                      path=run_dir, 
                      years=future_era,
                      kd=kd_avg, 
                      nml_args=c(list(
                        dt=3600, subdaily=FALSE, nsave=24, 
                        timezone=-6,
                        csv_point_nlevs=0, 
                        snow_albedo_factor=1.1, 
                        meteo_fl=driver_path, 
                        cd=getCD(site_id, method='Hondzo')), 
                        nml_args))
      
      wtr = get_temp(file.path(run_dir, 'output.nc'), reference='surface', z_out = get.offsets(wtr_all))
      ## drop the first n burn-in years
      #years = as.POSIXlt(wtr$DateTime)$year + 1900
      #to_keep = !(years <= min(years) + nburn - 1)
      #wtr = wtr[to_keep, ]
      
      wtr_all = rbind(wtr_all, wtr)
      
      core_metrics = rbind(core_metrics, necsc_thermal_metrics_core(run_dir, site_id))
      
      ##now hab
      hansen_habitat = rbind(hansen_habitat, hansen_habitat_calc(run_dir, lakeid=site_id))
    }
    
    unlink(run_dir, recursive=TRUE)
    
    all_data = list(wtr=wtr_all, core_metrics=core_metrics, hansen_habitat=hansen_habitat, site_id=site_id)

    return(all_data)
    
  }, error=function(e){
      unlink(run_dir, recursive=TRUE);
      return(list(error=e, site_id))
    })
}


driver_fun = function(site_id){
  nldas = read.csv(get_driver_path(site_id, driver_name = 'NLDAS'), header=TRUE)
  drivers = driver_nldas_wind_debias(nldas)
  drivers = driver_add_burnin_years(drivers, nyears=2)
  drivers = driver_add_rain(drivers, month=7:9, rain_add=0.5) ##keep the lakes topped off
  driver_save(drivers)
}

getnext = function(fname){
  i=0
  barefname = fname
  while(file.exists(fname)){
    i=i+1
    fname = paste0(barefname, '.', i)
  }
  return(fname)
}

wrapup_output = function(out, run_name, years){
  out_dir = file.path('D:/WiLMA_results/habitat', run_name)
  
  run_exists = file.exists(out_dir)
  
  if(!run_exists) {dir.create(out_dir, recursive=TRUE)}
  
  good_data = out[!unlist(lapply(out, function(x){'error' %in% names(x) || is.null(x)}))]
  bad_data  = out[unlist(lapply(out, function(x){'error' %in% names(x) || is.null(x)}))]
  
  sprintf('%i lakes ran\n', length(good_data))
  dframes = lapply(good_data, function(x){tmp = x[[1]]; tmp$site_id=x[['site_id']]; return(tmp)})
  #drop the burn-in years
  dframes = lapply(dframes, function(df){subset(df, DateTime > as.POSIXct('1979-01-01'))})
  
  hansen_habitat = do.call(rbind, lapply(good_data, function(x){x[['hansen_habitat']]}))
  hansen_habitat = subset(hansen_habitat, year %in% years)
  
  core_metrics = do.call(rbind, lapply(good_data, function(x){x[['core_metrics']]}))
  core_metrics = subset(core_metrics, year %in% years)
  
  
  write.table(hansen_habitat, file.path(out_dir, 'NLDAS_best_hansen_hab.tsv'), sep='\t', row.names=FALSE, append=run_exists, col.names=!run_exists)
  write.table(core_metrics, file.path(out_dir, 'NLDAS_best_core_metrics.tsv'), sep='\t', row.names=FALSE, append=run_exists, col.names=!run_exists)
  
  save('dframes', file = getnext(file.path(out_dir, 'NLDAS_best_all_wtr.Rdata')))
  save('bad_data', file = getnext(file.path(out_dir, 'NLDAS_bad_data.Rdata')))
  
  rm(out, good_data, dframes)
  gc()
}


#to_run = unique(get_driver_index('NLDAS')$id)
# 
# #set driver location to datascience computer
# clusterCall(c1, function(){library(mda.lakes);set_driver_url(driver_url)})
# 
# run_name = '2016-04-20_nldas_habitat_out'
# years = 1977:2015
# clusterExport(c1, 'secchi_standard')
# 
# out = clusterApplyLB(c1, to_run, future_hab_wtr, modern_era=1977:2015, 
#                      driver_function=driver_fun, secchi_function=secchi_standard)
# 
# wrapup_output(out, run_name, years=1979:2014)





################################################################################
## Lets run ACCESS 1980-1999, 2020-2039
################################################################################
driver_fun = function(site_id, gcm){
  drivers = read.csv(get_driver_path(paste0(site_id, ''), driver_name = gcm, timestep = 'daily'), header=TRUE)
  #nldas   = read.csv(get_driver_path(paste0(site_id, ''), driver_name = 'NLDAS'), header=TRUE)
  #drivers = driver_nldas_debias_airt_sw(drivers, nldas)
  drivers = driver_add_burnin_years(drivers, nyears=2)
  drivers = driver_add_rain(drivers, month=7:9, rain_add=0.5) ##keep the lakes topped off
  driver_save(drivers)
}
to_run = as.character(unique(zmax$site_id))
clusterExport(c1, 'driver_fun')
clusterExport(c1, 'secchi_standard')
driver_name = 'PRISM'
clusterExport(c1, 'driver_name')
clusterCall(c1, function(){library(mda.lakes);set_driver_url(driver_url)})

run_name = paste0('2016-05-12_', driver_name, '_habitat_out')

##1980-1999
runsplits = split(1:length(to_run), floor(1:length(to_run)/1e3))
yeargroups = list(1980:1999, 2020:2039, 2080:2099)

for(ygroup in yeargroups){
  for(rsplit in runsplits){
    start = Sys.time()
    out = clusterApplyLB(c1, to_run[rsplit], future_hab_wtr, 
                         modern_era=ygroup, 
                         secchi_function=secchi_standard,
                         driver_function=function(site_id){driver_fun(site_id, driver_name)})
    
    wrapup_output(out, run_name, years=ygroup)
    print(difftime(Sys.time(), start, units='hours'))
    cat('on to the next\n')
  }  
}

