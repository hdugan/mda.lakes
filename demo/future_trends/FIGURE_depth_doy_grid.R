# Lets make a stratification heat map
library(mda.lakes)
library(plyr)
library(dplyr)
library(rLakeAnalyzer)
library(reshape2)
library(lubridate)
library(mda.lakes)
#Analyze!

#load('~/FUTURE_GENMOM.Rdata')
site_ids = unlist(lapply(dframes, function(l){l$site_id[1]}))

#bathy = getBathy('805400')
#names(bathy) = c('depths', 'areas')

tmp = dframes[[which(site_ids=='WBIC_1881900')]]

tmp$site_id = NULL
tmp$DateTime = as.POSIXct(tmp$DateTime)
names(tmp) = tolower(names(tmp))
long = melt(tmp, id.vars='datetime', value.name = 'temp', variable.name = 'depth', factorsAsStrings=TRUE)
long$depth = as.numeric(sapply(as.character(long$depth), function(x){substr(x,5,nchar(x))}))


wtr_sens = sens_seasonal_site(year(long$datetime), long$temp, yday(long$datetime), long$depth)

grid_df = ddply(wtr_sens, c('sites_i', 'season_i'), function(df){data.frame(slope=median(df$slopes, na.rm=TRUE), num=nrow(df))})

grid_df = grid_df[grid_df$num > 100,]

grid_mat = dcast(grid_df, sites_i~season_i, median, value.var='slope')
grid_mat = grid_mat[complete.cases(grid_mat), ]

y = grid_mat[,1]
x = as.numeric(names(grid_mat)[-1])

grid_mat = grid_mat[,-1]
cols = colorRampPalette(colors=c('blue','white', 'red'))(12)

png('~/nldas.grid.sens.sp.png', res=300, width=2000, height=1500)
image(x, y, t(as.matrix(grid_mat)), ylim=rev(range(y)), col=cols, zlim=c(-0.1,0.1), 
      xlab='Day of Year', ylab='Depth')
dev.off()

png('~/nldas.season.sens.me.png', res=300, width=2000, height=1500)
boxplot(slopes~season_i, wtr_sens, ylim=c(-0.1, 0.1), xlab="Day of Year", ylab='Trend')
abline(0,0)
dev.off()

png('~/nldas.depths.sens.me.png', res=300, width=2000, height=1500)
boxplot(slopes~sites_i, wtr_sens, ylim=c(-0.1, 0.1), ylab='Trend', xlab="Depth")
abline(0,0)
dev.off()

