function getDriverDataGDP

clc
clear all
%% -- variables --
timerPeriod = 42;    % seconds
retries = 5;

daily = true;

writeDir= '/Users/jread/Desktop/Science Projects/WiLMA/Driver data/';
GeoServ = 'https://www.sciencebase.gov/catalogMaps/mapping/ows/50d35261e4b062c7914ebd14';

baseURL = 'dods://www.esrl.noaa.gov/psd/thredds/dodsC/Datasets/NARR/';
if daily
    baseURL = [baseURL 'Dailies/'];
    writeDir= [writeDir 'Dailies/'];
end

SW_URI  = [baseURL 'monolevel/dswrf.YYYY.nc'];
LW_URI  = [baseURL 'monolevel/dlwrf.YYYY.nc'];
air_URI = [baseURL 'monolevel/air.2m.YYYY.nc'];
uwnd_URI= [baseURL 'monolevel/uwnd.10m.YYYY.nc'];
vwnd_URI= [baseURL 'monolevel/vwnd.10m.YYYY.nc'];
prcp_URI= [baseURL 'monolevel/apcp.YYYY.nc'];
RH_URI  = [baseURL 'monolevel/rhum.2m.YYYY.nc'];
snow_URI= [baseURL 'monolevel/weasd.YYYY.nc'];
%snowZ_URI=[baseURL 'monolevel/snod.YYYY.nc'];
%CC_URI  = [baseURL 'monolevel/tcdc.YYYY.nc'];

WPS_URL = 'http://cida.usgs.gov/gdp/process/WebProcessingService';


dswrf= struct('uri',SW_URI,'fileName','SW_NARR');
dlwrf= struct('uri',LW_URI,'fileName','LW_NARR');
air  = struct('uri',air_URI,'fileName','air_NARR');
uwnd = struct('uri',uwnd_URI,'fileName','uwnd_NARR');
vwnd = struct('uri',vwnd_URI,'fileName','vwnd_NARR');
apcp = struct('uri',prcp_URI,'fileName','prcp_NARR');
rhum = struct('uri',RH_URI,'fileName','RH_NARR');
weasd= struct('uri',snow_URI,'fileName','snow_NARR');
%snod = struct('uri',snowZ_URI,'fileName','snowZ_NARR');
%tcdc = struct('uri',CC_URI,'fileName','CC_NARR');


VarSets = struct(...
    'weasd',weasd,'dswrf',dswrf,'dlwrf',dlwrf,'air',air,...
    'rhum',rhum,'vwnd',vwnd,'uwnd',uwnd,'apcp',apcp)

feature_collection = 'sb:managedLakesAllOne';
attribute = 'WBDY_WBIC'; % for WBIC codes... 

years = 1984:-1:1980;

%% set processing

vars = fieldnames(VarSets);

for i = 1:length(years)
    YYYY = num2str(years(i));
    % create folder if it doesn't exist
    mkdir(writeDir,YYYY)
    for v = 1:length(vars)
        tic
        GDP = mGDP();
        
        GDP = GDP.setGeoserver(GeoServ);
        GDP = GDP.setWPS(WPS_URL);
        GDP = GDP.setFeature('FEATURE_COLLECTION',feature_collection,...
            'ATTRIBUTE',attribute,'GML','NULL');
            
        URI = regexprep(VarSets.(vars{v}).uri,'YYYY',YYYY);
        disp(URI)
        var = vars{v};
        GDP = GDP.setPostInputs('DATASET_ID',var,...
            'TIME_START',[YYYY '-01-01T00:00:00.000Z'],...
            'TIME_END',  [YYYY '-12-31T21:00:00.000Z']);
        GDP = GDP.setDatasetURI(URI);
        GDP = GDP.executePost;
        attempt = 1;
        retry = false;
        done = false;
        
        % now loop and check 
        while ~done
            toc
            pause(timerPeriod)
            if retry && ~gt(attempt,retries)
                GDP = GDP.executePost;
                attempt = attempt+1;
                retry = false;
            elseif retry
                done = true;
                disp(['Process failed after ' num2str(attempt)...
                    ' attempts']);
            end
            fileNm = VarSets.(var).fileName;
            if ~done    % if still not done
                disp(['currently working on ' var]);
                
                % status can be failed, complete, incomplete, none, or unknown
                [f_Handle,status] = GDP.checkProcess;   % check again
                if strcmp(status,'failed')
                    retry = true;       % need to try again with execute
                elseif strcmp(status,'complete')
                    done = true;
                elseif strcmp(status,'none')
                    error('no process started')
                end
                
                
                if done  % will be first time that done is true
                    disp(['***** writing ' YYYY '/' fileNm '.txt *****']);
                    urlwrite(f_Handle,[writeDir YYYY '/' fileNm '.txt']);cd ..
                end
            elseif done && retry
                disp(['#$(&@#& '  var ' process failed #$&(@#$'])
            else
                disp(['*----' var ' process complete----*'])
            end    
            disp(status)
        end
        clear GDP     
    end
end

