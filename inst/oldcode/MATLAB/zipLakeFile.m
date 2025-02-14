function zipLakeFile(lakeNm,appendNm,rootDir,zipDir)
% aggregates names, appends a name to the begining of the zip file,
% re-writes the .prj file for each lake (to conform to prj2epsg web
% services)

% - lakeNm must be a string

if eq(nargin,1)
    appendNm = 'WiLMA_lake_';
    rootDir = '/Volumes/projects/WiLMA/rawLakes/';
    zipDir  = '/Volumes/projects/WiLMA/zippedLakes/';
end

if ~ischar(lakeNm)
    error('lake name input must be a string')
end

%% -- variables --


prjWrite = ['GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'...
    'SPHEROID["WGS_1984",6378137,298.257223563]],PRIMEM'...
    '["Greenwich",0],UNIT["Degree",0.017453292519943295]]'];
files = {[lakeNm '.dbf'],[lakeNm '.prj'],...
    [lakeNm '.shx'],[lakeNm '.shp']};
replcPrj = true;

%% begin function
if replcPrj
    fID = fopen([rootDir lakeNm '.prj'],'w');
    fwrite(fID,prjWrite);
end

zFile = [zipDir appendNm lakeNm];

zip(zFile,files,rootDir)  


end

