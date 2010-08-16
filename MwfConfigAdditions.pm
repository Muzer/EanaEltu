# EANA ELTU THINGS
# Add this to your MwfConfig.pm

$cfg->{EE} = {};
$cfg->{EE}{demonFile} = '/tmp/change/me';
$cfg->{EE}{demonKey}= 'CHANGEMETOAVALIDKEY';
$cfg->{EE}{ftp} = {};
$cfg->{EE}{ftp}{server} = 'CHANGEME';
$cfg->{EE}{ftp}{user} = 'CHANGEME';
$cfg->{EE}{ftp}{password} = 'CHANGEME';
$cfg->{EE}{ftp}{dir} = 'CHANGEME';
$cfg->{EE}{tmpDir} = '/tmp/changeme';

# EE Addon stuff
$cfg->{EE}{addonBasename} = 'NaviDictionary';
$cfg->{EE}{addons} = [qw(MwfPlgNaviTSV MwfPlgNaviJM)];

#-----------------------------------------------------------------------------