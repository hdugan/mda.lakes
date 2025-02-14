# Functions for NHD linked drivers NLDAS and Hostetler
#
#
#

get_driver_nhd = function(id, driver_name, loc_cache, timestep){
	
	hostetler_names = c('ECHAM5', 'CM2.0', 'GENMOM')
	
	#get index
	indx = get_driver_index(driver_name, loc_cache)
	
	#match id to index
	match_i = which(indx$id == id)
	if(length(match_i) < 6){
		stop('flawed or missing driver set for ', id)
	}
	
	driver_df  = data.frame()
	driver_env = new.env()
	#grab (and open?) Rdata files
	for(i in 1:length(match_i)){
		fname = indx[match_i[i], 'file.name']
		driver_url = paste0(pkg_info$dvr_url, 'drivers_GLM_', driver_name, '/', fname)
		dest = file.path(tempdir(), driver_name, fname)
		
		
		if(substr(driver_url, 0,7) == 'file://'){
		  dest = sub('file://', '', driver_url)
		 #if driver url is a zip file, pull out of zip
		}else if(substr(pkg_info$dvr_url, nchar(pkg_info$dvr_url)-3,nchar(pkg_info$dvr_url)) == '.zip'){
			
			unzip(pkg_info$dvr_url, files = paste0('drivers_GLM_', driver_name, '/', fname), exdir=dirname(dest), junkpaths=TRUE)
			
		}else{
		  if(!download_helper(driver_url, dest)){
		    stop('failure downloading ', fname, '\n')
		  }
		}
		
		load(dest, envir=driver_env)
		driver_env[[indx[match_i[i], 'variable']]] = driver_env[['data.site']]
	}
	
	rm('data.site', envir=driver_env)
	
	#create and save formatted dataframe
	all_drivers = Reduce(function(...) merge(..., by='DateTime'), lapply(ls(driver_env), function(x)driver_env[[x]]))
	
	all_drivers = na.omit(all_drivers)
	
	glm_drivers = drivers_to_glm(all_drivers)

	
	
	if(timestep=='daily'){
		daily = trunc(as.POSIXct(glm_drivers$time), units='days')
		glm_drivers$time = format(daily,'%Y-%m-%d %H:%M:%S')
		
		glm_drivers = plyr::ddply(glm_drivers,'time', function(df){
			
			data.frame(
				ShortWave = mean(df$ShortWave),
				LongWave  = mean(df$LongWave),
				AirTemp   = mean(df$AirTemp),
				RelHum    = mean(df$RelHum),
				WindSpeed = mean(df$WindSpeed^3)^(1/3),
				Rain      = mean(df$Rain),
				Snow      = mean(df$Snow)
			)
		})
		
	}
	
	dest = paste0(tempdir(), '/', driver_name, '/', id, '.csv')
	if(!file.exists(dirname(dest))){
		dir.create(dirname(dest), recursive=TRUE)
	}
	
	write.table(glm_drivers, dest, sep=',', row.names=FALSE, col.names=TRUE, quote=FALSE)
	
	return(dest)
}

#' @title Return the driver file index table
#' 
#' @inheritParams get_driver_path
#' 
#' @description 
#' Accesses and returns the driver file index. Can be used to get list of 
#' all available driver data for a given driver
#' 
#' @examples 
#' unique(get_driver_index('NLDAS')$id)
#' 
#' @export
get_driver_index = function(driver_name, loc_cache=TRUE){
	#see if index file exists already
	index_url = paste0(pkg_info$dvr_url, 'drivers_GLM_', driver_name, '/driver_index.tsv')
	dest = file.path(tempdir(), driver_name, 'driver_index.tsv')
	
	#If it exists, return without downloading
	if(file.exists(dest) && loc_cache){
		return(read.table(dest, sep='\t', header=TRUE, as.is=TRUE))
	}
	
	if(substr(pkg_info$dvr_url, nchar(pkg_info$dvr_url)-3,nchar(pkg_info$dvr_url)) == '.zip'){
		unzip(pkg_info$dvr_url, files = paste0('drivers_GLM_', driver_name, '/driver_index.tsv'), exdir=dirname(dest), junkpaths=TRUE)
	}else if(substr(index_url, 1,7) == 'file://'){
	  
	  dest = index_url
	  
	}else{
		if(!download_helper(index_url, dest)){
			stop('driver_index.tsv: unable to download for driver data:', driver_name)
		}
	}
	
	return(read.table(dest, sep='\t', header=TRUE, as.is=TRUE))
}

#' @title Set driver URL
#' 
#' @param url New base URL to set
#' 
#' @description 
#' Sets the default URL to access driver data. 
#' 
#' @export
set_driver_url = function(url){
  pkg_info$dvr_url = url
}

drivers_to_glm = function(driver_df){
	
	## convert and downsample wind
	driver_df$ShortWave = driver_df$dswrfsfc
	driver_df$LongWave  = driver_df$dlwrfsfc
	
	if('windspeed' %in% names(driver_df)){
		driver_df$WindSpeed = driver_df$windspeed
	}else if('ugrd10m' %in% names(driver_df)){
		driver_df$WindSpeed = sqrt(driver_df$ugrd10m^2 + driver_df$vgrd10m^2)
	}else{
		stop('Unable to find wind data.\nDriver service must have temp data (named windspeed or ugrd10m). ')
	}
	
	
	
	##TODO Maybe: Generalize these conversions so they aren't if/else statements
	if('tmp2m' %in% names(driver_df)){
		driver_df$AirTemp   = driver_df$tmp2m - 273.15 #convert K to deg C
	}else if('airtemp' %in% names(driver_df)){
		driver_df$AirTemp   = driver_df$airtemp #no conversion neede
	}else{
		stop('Unable to find temperature data.\nDriver service must have temp data (named tmp2m or airtemp). ')
	}
	
	if('relhum' %in% names(driver_df)){
		driver_df$RelHum    = 100*driver_df$relhum
	}else if('spfh2m' %in% names(driver_df)){
		driver_df$RelHum    = 100*driver_df$spfh2m/qsat(driver_df$tmp2m-273.15, driver_df$pressfc*0.01)
	}else if('relhumperc' %in% names(driver_df)){
		driver_df$RelHum    = driver_df$relhumperc
	}else{
		stop('Unable to find humidity data.\nDriver service must have humidity data (named relhum or spfh2m). ')
	}
	
	if('apcpsfc' %in% names(driver_df)){
		#convert from mm/hour to m/day
		driver_df$Rain      = driver_df$apcpsfc*24/1000 #convert to m/day rate
	}else if('precip' %in% names(driver_df)){
		#convert from mm/day to m/day
		driver_df$Rain      = driver_df$precip/1000
	}else{
		stop('Unable to find precipitation data. \nMust be either apcpsfc or precip')
	}
	
	
	#now deal with snow base case
	driver_df$Snow = 0
	
	# 10:1 ratio assuming 1:10 density ratio water weight
	driver_df$Snow[driver_df$AirTemp < 0] = driver_df$Rain[driver_df$AirTemp < 0]*10 
	driver_df$Rain[driver_df$AirTemp < 0] = 0
	
	
	#convert DateTime to properly formatted string
	driver_df$time = driver_df$DateTime
	driver_df$time = format(driver_df$time,'%Y-%m-%d %H:%M:%S')
	
	return(driver_df[order(driver_df$time), c('time','ShortWave','LongWave','AirTemp','RelHum','WindSpeed','Rain','Snow')])
}

