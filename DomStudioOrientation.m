function DomStudioOrientation(~)
% @ 2015 by Andrea Bistacchi, distributed under the GNU AGPL v3.0 license.
%
% Function used for the analysis of orientation data imported as CSV files with Dip / Dip Azimuth
%
% Contributions by Andrea Bistacchi and Stefano Casiraghi (k-medoids)
% Last update by Andrea Bistacchi 27/5/2024

% initialize including parallel pool (if not yet active)
clear all; close all; clc; clearvars;
if isempty(gcp('nocreate')), parpool('Threads',gpuDeviceCount("available")); end
addpath("kuipertest")
rad = pi/180;
deg = 180/pi;
cmap =[ones(1,10)' linspace(1,0,10)' linspace(1,0,10)'];

% INPUT AND CHECK DATA

% file overwrite warning
disp(' ')
disp('---- WARNING: this script overwrites output files without asking for confirmaton ----')

% load CSV file with orientation data
[file, path] = uigetfile('*.csv');
filename = [path file];
[~,~,ext] = fileparts(filename);
inDataTable = readtable(filename);
filename = erase(filename,ext);

% file info
disp(' ')
disp(['Column names recorded in file header are: ' inDataTable.Properties.VariableNames])
disp(' ')
disp('Import data as [1]:')
disp('   1: Dip Direction / Dip')
disp('   2: Dip / Dip Direction')
disp('   3: Trend / Plunge')
disp('   4: Plunge / Trend')
disp('else: abort importing')
commandwindow
inDataFormat = input('>> ');
if isempty(inDataFormat), inDataFormat = 1; end

% Copy formatted data to variables. If dip/direction is input, it is
% converted to plunge/trend to calculate poles, and viceversa. Strike
% is calculated only for planes imported as dip/direction.
if inDataFormat == 1
    DipDirection = inDataTable.(1);
    Dip = inDataTable.(2);
    Plunge = 90-Dip;
    Trend = (DipDirection<=180).*(DipDirection+180)+(DipDirection>180).*(DipDirection-180);
    Strike = (DipDirection<90).*(DipDirection+270) + (DipDirection>=90).*(DipDirection-90);
elseif inDataFormat == 2
    DipDirection = inDataTable.(2);
    Dip = inDataTable.(1);
    Plunge = 90-Dip;
    Trend = (DipDirection<=180).*(DipDirection+180)+(DipDirection>180).*(DipDirection-180);
    Strike = (DipDirection<90).*(DipDirection+270) + (DipDirection>=90).*(DipDirection-90);
elseif inDataFormat == 3
    Trend = inDataTable.(1);
    Plunge = inDataTable.(2);
    Dip = 90-Plunge;
    DipDirection = (Trend<=180).*(Trend+180)+(Trend>180).*(Trend-180);
    Strike = [];
elseif inDataFormat == 4
    Trend = inDataTable.(2);
    Plunge = inDataTable.(1);
    Dip = 90-Plunge;
    DipDirection = (Trend<=180).*(Trend+180)+(Trend>180).*(Trend-180);
    Strike = [];
else
    error('---- NO FORMAT SELECTED - aborting ----');
end

% Ndata = number of data points
Ndata = size(inDataTable,1);
disp(' ')
disp(['Number of data loaded: ' num2str(Ndata)])

% check data
if max(Dip)>90 || min(Dip)<0, error('---- DIP ERROR - aborting ----'); end
if max(DipDirection)>360 || min(DipDirection)<0, error('---- AZIMUTH ERROR - aborting ----'); end
if max(Plunge)>90 || min(Plunge)<0, error('---- PLUNGE ERROR - aborting ----'); end
if max(Trend)>360 || min(Trend)<0, error('---- TREND ERROR - aborting ----'); end

% direction cosines of pole vectors in lower hemisphere (-sin)
Lpole = cos(Plunge*rad).*cos(Trend*rad);
Mpole = cos(Plunge*rad).*sin(Trend*rad);
Npole = -sin(Plunge*rad);

% union of original unit vectors and symmetric unit vectors in upper
% hemisphere ("reflected unit vectors") -> arrays are twice the length of input data
Lpole = [Lpole; -Lpole];
Mpole = [Mpole; -Mpole];
Npole = [Npole; -Npole];

% also original input data are duplicated to keep everything consistent, but
% without reflecting them on the upper sphere (not necessary)
DipDirection = [DipDirection; DipDirection];
Dip = [Dip; Dip];
Trend = [Trend; Trend];
Plunge = [Plunge; Plunge];
Strike = [Strike; Strike];

% END INPUT AND CHECK DATA

% STEREOPLOT & ROSE
fig_1 = figure('WindowStyle','docked');

% plot and label contours
fig_1_1 = subplot(1,3,1);
max_conc = contour_plot(Lpole, Mpole, Npole, fig_1_1);
title({'Equal-area contour pole plot';' '})

% Plot rose diagram. Strike used for planes and Trend for lines.
fig_1_2 = subplot(1,3,2);
if isempty(Strike)
    rose_plot(Trend(1:Ndata,:), fig_1_2);
    title({'Trend rose plot';' '})
else
    rose_plot(Strike(1:Ndata,:), fig_1_2);
    title({'Strike rose plot';' '})
end

% create empty subplot used to show summary text at the end
fig_1_3 = subplot(1,3,3);
axis off

% END STEREOPLOT & ROSE

% K-MEDOID CLUSTERING
while 1
    % clustering options
    while 1
        disp(' ')
        disp('Clustering options [1]:')
        disp('   1: input centroids with mouse')
        disp('   2: automatic K-medoid centroids')
        commandwindow
        inDataFormat = input('>> ');
        if isempty(inDataFormat), inDataFormat = 1; end
        if inDataFormat == 1 || inDataFormat == 2, break; end
    end

    if inDataFormat == 1
        % add seeds for k-medoid or k-meand with mouse click (ginput)
        axes(fig_1_1)
        disp(' ')
        disp('Collect class centroids with left mouse click. Any other click ends picking.')
        in_pp = [];
        in_tt=[];
        while 1,
            % collect coords and convert to plunge/trend arrays
            [x,y,button] = ginput(1);
            if button ~= 1; break; end
            in_t = atan2(x,y)*deg;
            in_p = 90 - asin(sqrt(x^2 + y^2)/ sqrt(2))*2*deg;
            in_t = in_t + 360*(in_t<0);
            disp(['Picked centroid [plunge/trend]: ' num2str(in_p, '%.0f') '/' num2str(in_t, '%.0f')])
            in_pp = [in_pp; in_p];
            in_tt = [in_tt; in_t];
        end

        % check if at least one class has been picked, otherwise create
        % single plunge/trend = 00/000
        if isempty(in_pp)
            in_pp = 0;
            in_tt = 0;
        end

        % direction cosines of pole vectors in lower hemisphere (-sin)
        in_L = cos(in_pp*rad).*cos(in_tt*rad);
        in_M = cos(in_pp*rad).*sin(in_tt*rad);
        in_N = -sin(in_pp*rad);

        % union of unit vectors in both hemispheres -> arrays are twice the length of input data
        in_L = [in_L; -in_L];
        in_M = [in_M; -in_M];
        in_N = [in_N; -in_N];

        % Find data vectors closer to picked centroids. This is necessary since
        % the starting values in kmedoids must be chosen among input data.
        nClass = length(in_L);
        for i = 1:nClass
            dist = sqrt((Lpole-in_L(i)).^2 + (Mpole-in_M(i)).^2 + (Npole-in_N(i)).^2);
            min_id = find(dist == min(dist));
            in_L(i) = Lpole(min_id);
            in_M(i) = Mpole(min_id);
            in_N(i) = Npole(min_id);
        end

        % clustering with k-medoids
        idClass = kmedoids([Lpole Mpole Npole],nClass,'Options',statset('UseParallel',true),'Start',[in_L in_M in_N]);

    else
        % k-medoids with automatic seed initialization
        disp(' ')
        disp('Number of classes for K-medoid clustering [1]:')
        commandwindow
        nClass = input('>> ');
        if isempty(nClass), nClass = 1; end
        if nClass < 1, nClass = 1; end
        nClass = round(nClass)*2;
        % clustering with k-medoids
        idClass = kmedoids([Lpole Mpole Npole],nClass,'Options',statset('UseParallel',true));
    end

    % count classes
    countClass = zeros(1,nClass);
    for i = 1:nClass
        countClass(i) = sum(idClass==i);
    end
    countClassPercent = countClass./Ndata.*100;

    % FISHER STATISTICS & CLASS CONTOURING

    % Fisher's mean and K
    for i = 1:nClass
        disp(' ')
        disp(['Class: ' num2str(i)])

        % calculate stats
        % mean unit vector
        sumL = sum(Lpole(idClass==i));
        sumM = sum(Mpole(idClass==i));
        sumN = sum(Npole(idClass==i));
        R = sqrt(sumL^2+sumM^2+sumN^2);
        sumLR(i) = sumL/R;
        sumMR(i) = sumM/R;
        sumNR(i) = sumN/R;
        meanP = asin(-sumNR(i))*deg;
        meanT = atan2(sumMR(i),sumLR(i))*deg;
        meanT = meanT+(meanT<0)*360;

        % Fisher K calculated with standard formulas from geology
        % textbooks, that is different with n_data >= or < 16
        % alternative formulas are:
        % fisherK(i) = R/countClass(i)*(3-(R/countClass(i))^2)/(1-(R/countClass(i))^2) % Banerjee 2005
        % fisherK(i) = 1/(1-R/countClass(i)) % Mardia & Jupp 2000, p. 214
        if countClass(i) >= 16
            fisherK(i) = (countClass(i)-1)/(countClass(i)-R);
        else
            fisherK(i) = countClass(i)/(countClass(i)-R)*(1 - 1/countClass(i))^2;
            disp('---- WARNING: n data < 16 ----')
        end

        % confidence cone apical angle
        confC(i) = asin( 1 - (countClass(i)-R)/R * ((1/0.01)^(1/(countClass(i)-1)) - 1) )*deg;
        spherAp(i) = asin(sqrt(2*(1-1/countClass(i))/fisherK(i)))*deg;

        % mean dip/dir and plunge/trend
        meanDip(i) = 90-meanP;
        meanDir(i) = (meanT<=180).*(meanT+180)+(meanT>180).*(meanT-180);
        meanPlunge(i) = meanP;
        meanTrend(i) = meanT;
        disp(['Dip: ' num2str(meanDip(i)) '   Dir: ' num2str(meanDir(i)) '   K: ' num2str(fisherK(i))])
        clear sumL sumM sumN R meanP meanT
    end

    % remove classes with mean vectors pointing upwards (but reflected poles
    % are kept since they are used later on)
    keep_class = find(meanDip<=90);
    countClass = countClass(meanDip<=90);
    countClassPercent = countClassPercent(meanDip<=90);
    fisherK = fisherK(meanDip<=90);
    confC = confC(meanDip<=90);
    spherAp = spherAp(meanDip<=90);
    meanPlunge = meanPlunge(meanDip<=90);
    meanTrend = meanTrend(meanDip<=90);
    meanDir = meanDir(meanDip<=90);
    meanDip = meanDip(meanDip<=90); % this must be the last one
    nClass = nClass/2;
    disp(' ')
    disp('Fisher means and Ks done')

    % GOF for Fisher's statistics according to:
    % Fisher, N. I., Lewis, T., and Embleton, B. J. J.
    % 1987
    % Statistical analysis of spherical data
    % Cambridge University Press
    % and references therein by the same authors
    for i = 1:nClass
        class = keep_class(i);
        disp(' ')
        disp(['class: ' num2str(class)])
        disp(['Mean Plunge(i): ' num2str(meanPlunge(i))])
        disp(['Mean Trend:     ' num2str(meanTrend(i))])
        disp(['Fisher K:       ' num2str(fisherK(i))])

        % create subplots if they do not exixt
        try
            findall(0,'type','figure','name',fig_2(i));
        catch
            fig_2(i) = figure('WindowStyle','docked');
            sgtitle(['Class ID = ' num2str(class)])
            fig_2_1(i) = subplot(2,4,1);
            fig_2_2(i) = subplot(2,4,2);
            fig_2_3(i) = subplot(2,4,3);
            fig_2_4(i) = subplot(2,4,4);
            fig_2_5(i) = subplot(2,4,5);
            fig_2_6(i) = subplot(2,4,6);
            fig_2_7(i) = subplot(2,4,7);
            fig_2_8(i) = subplot(2,4,8);
        end

        % manage errors in Fisher test
        try
            % collect data for this class
            cartCords = [Lpole(idClass==class)';
                         Mpole(idClass==class)';
                         Npole(idClass==class)'];

            %plot and label contours for class
            max_conc_class(i) = contour_plot(cartCords(1,:), cartCords(2,:), cartCords(3,:), fig_2_1(i));
            title({'Equal-area contour pole plot';' '})

            % plot rose diagram for this class
            if isempty(Strike)
                rose_plot(Trend(find(ismember(idClass, class)),:), fig_2_5(i));
                title({'Trend rose plot';' '})
            else
                rose_plot(Strike(find(ismember(idClass, class)),:), fig_2_5(i));
                title({'Strike rose plot';' '})
            end            

            % plot summary for this class
            axes(fig_2_8(i))
            axis off
            outcome = { ...
                ['                        Class ID = ' num2str(keep_class(i),'%12d')         ];...
                ['                  Poles in class = ' num2str(countClass(i),'%12d')         ];...
                ['                      % of total = ' num2str(countClassPercent(i),'%12.2f')];...
                ['                        Mean Dir = ' num2str(meanDir(i),'%12.2f')          ];...
                ['                        Mean Dip = ' num2str(meanDip(i),'%12.2f')          ];...
                ['                               K = ' num2str(fisherK(i),'%12.2f')          ];...
                ['            99% conf. cone angle = ' num2str(confC(i),'%12.2f')            ];...
                ['  68.26% variability sph. apert. = ' num2str(spherAp(i),'%12.2f')          ];...
                [''                                                                       ];...
                ['Max conc. % of total per 1% area = ' num2str(max_conc_class(i),'%12.2f')      ] ...
                };
            text(0,0.4,outcome','HorizontalAlignment','left','VerticalAlignment','top','FontName','Courier');

            % define alpha, beta in rad
            alpha = meanPlunge(i)*rad;
            beta =  meanTrend(i)*rad;

            % rotate original data to mean pole (alpha, beta) with rotation
            % matrix A_prime, obtained from rotation vector axis_prime and
            % rotation angle angle_prime
            axis_prime = cross([sumLR(class) sumMR(class) sumNR(class)], [0 0 1]);
            angle_prime = acos(dot([sumLR(class) sumMR(class) sumNR(class)], [0 0 1]));
            axis_prime = axis_prime / sin(angle_prime);
            % disp(' '); disp('axis_prime'); disp(atan2(axis_prime(2), axis_prime(1))*deg); disp('angle_prime'); disp(angle_prime*deg);
            A_prime = axang2rotm([axis_prime angle_prime]);
            cartCords_prime = A_prime * cartCords;

            % calculate rotated polar coords in rad
            theta_prime = acos(cartCords_prime(3,:)); % non-geological spherical coords use acos (geological use -asin)
            phi_prime = atan2(cartCords_prime(2,:), cartCords_prime(1,:));  % y then x

            % show rotated poles in polar plot
            axes(fig_2_2(i))
            hold off
            plot(cos(linspace(0,2*pi,180)), sin(linspace(0,2*pi,180)),'k-')
            hold on
            plot(sqrt(2) * sin(-theta_prime/2).* sin(phi_prime), ...
                sqrt(2) * sin(-theta_prime/2).* cos(phi_prime), ...
                'o');
            axis equal
            axis tight
            set(gca,'XTick',[], 'YTick', [])
            title({'Original data rotated to';...
                'mean pole (\alpha, \beta)'})

            %draw grid for primitive circle with standard radius = 1
            for d = sqrt(2) * sin((10:10:80)*rad/2)
                xNodes = d * cos(linspace(0,2*pi,180));
                yNodes = d * sin(linspace(0,2*pi,180));
                plot(xNodes,yNodes,'LineWidth',0.5,'Color',[.5 .5 .5])
            end
            for d = (10:10:180)*rad
                xNodes = [cos(d) -cos(d)];
                yNodes = [sin(d) -sin(d)];
                plot(xNodes,yNodes,'LineWidth',0.5,'Color',[.5 .5 .5])
            end

            % X_a = 1 - cos(theta_prime) should be exponentially distributed
            % E(1/FisherK) if FisherK >3. Test with KS.
            % ----------
            % Note that Fisher & Best, 1987, write E(FisherK), buth this should be
            % an error, or a different diefinition of FisherK, since there is no way
            % to fit E(FisherK). 1/FisherK seems OK because for larger FisherK the
            % std dev should be smaller.
            % ----------
            X_a = 1 - cos(theta_prime);

            % empirical cumulative distribution
            [~,X_a_ecdf] = ecdf(X_a);
            % create exponential distribution E(1/FisherK)
            expDist = makedist('Exponential','mu',1/fisherK(i));
            expPDF = pdf(expDist,X_a_ecdf);

            % Kolmogorov-Smirnov test
            [ExpLHo,ExpLPval,~,~] = kstest(X_a,'CDF',expDist);
            disp(' ')
            disp('Kolmogorov-Smirnov GOF test for 1 - cos(theta_prime):')
            if ExpLHo == 0
                outcome = {'Exponential dist. E(1/K)';...
                    'ACCEPTED at 5% sign.';...
                    ['with P-value = ' num2str(ExpLPval)]};
            else
                outcome = {'Exponential dist. E(1/FisherK)';...
                    'REJECTED at 5% sign.';...
                    ['with P-value = ' num2str(ExpLPval)]};
            end
            disp(outcome);

            % plot exponential test
            axes(fig_2_3(i))
            hold off
            histogram(X_a,'Normalization','pdf','FaceColor',[.6 .6 .6]);
            hold on
            plot(X_a_ecdf,expPDF,'r','linewidth',2)
            grid on
            set(gca, 'PlotBoxAspectRatio', [1,2,1])
            title(outcome);

            % X_b = phi_prime should be uniformly distributed U(0, 2pi)
            % or X_b = phi_prime / 2pi should be uniformly distributed U(0,1))
            % Test with Kuiper thanks to:
            % https://it.mathworks.com/matlabcentral/fileexchange/50158-kuiper-test
            X_b = phi_prime;
            X_b = X_b + 2*pi*(X_b<0);

            % empirical cumulative distribution
            [~,X_b_ecdf] = ecdf(X_b);

            % create uniform distribution U(0, 2pi)
            uniDist = makedist('Uniform','lower',0,'upper',2*pi);
            uniPDF = pdf(uniDist,X_b_ecdf);

            % Kuiper test
            [UniLHo,UniLPval,~,~] = kuipertest(X_b,'CDF',uniDist);
            disp(' ')
            disp('Kuiper GOF test for phi_prime / 2pi:')
            if UniLHo == 0
                outcome = {'Uniform dist. U(0, 2\pi)';...
                    'ACCEPTED at 5% sign.';...
                    ['with P-value = ' num2str(UniLPval)]};
            else
                outcome = {'Uniform dist. U(0, 2\pi)';...
                    'REJECTED at 5% sign.';...
                    ['with P-value = ' num2str(UniLPval)]};
            end
            disp(outcome);

            % plot normal test
            axes(fig_2_4(i))
            hold off
            histogram(X_b,'Normalization','pdf','FaceColor',[.6 .6 .6],'BinLimits',[0 2*pi]);
            hold on
            plot(X_b_ecdf,uniPDF,'r','linewidth',2)
            xticks([0 .5*pi pi 1.5*pi 2*pi])
            xticklabels({'0', '\pi/2', '\pi', '3/2\pi', '2\pi'})
            grid on
            set(gca, 'PlotBoxAspectRatio', [1,2,1])
            title(outcome);

            % rotate original data to mean pole (3pi/2 - alpha, beta - pi) with rotation
            % matrix A_second, obtained from rotation vector axis_second and
            % rotation angle angle_second
            axis_second = cross([sumLR(class) sumMR(class) sumNR(class)], ...
                [cos(-pi)*cos(3*pi/2) sin(-pi)*cos(3*pi/2) -sin(3*pi/2)]);
            angle_second =  acos(dot([sumLR(class) sumMR(class) sumNR(class)], ...
                [cos(-pi)*cos(3*pi/2) sin(-pi)*cos(3*pi/2) -sin(3*pi/2)]));
            axis_second = axis_second / sin(angle_second);
            % disp(' '); disp('axis_second'); disp(atan2(axis_second(2), axis_second(1))*deg); disp('angle_second'); disp(angle_second*deg);
            A_second = axang2rotm([axis_second angle_second]);
            cartCords_second = A_second * cartCords;

            % calculate rotated polar coords in rad
            theta_second = acos(cartCords_second(3,:)); % non-geological spherical coords use acos (geological use -asin)
            phi_second = atan2(cartCords_second(2,:), cartCords_second(1,:));  % y then x
            phi_second = phi_second -2*pi*(phi_second>pi);

            % show rotated poles in polar plot
            axes(fig_2_6(i))
            hold off
            plot(cos(linspace(0,2*pi,180)), sin(linspace(0,2*pi,180)),'k-')
            hold on
            plot(sqrt(2) * sin(theta_second/2).* sin(phi_second), ...
                sqrt(2) * sin(theta_second/2).* cos(phi_second), ...
                'o');
            axis equal
            axis tight
            set(gca,'XTick',[], 'YTick', [])
            title({'Original data rotated to';...
                'mean pole (3/2\pi - \alpha, \beta - \pi)'})

            %draw grid for primitive circle with standard radius = 1
            for d = sqrt(2) * sin((10:10:80)*rad/2)
                xNodes = d * cos(linspace(0,2*pi,180));
                yNodes = d * sin(linspace(0,2*pi,180));
                plot(xNodes,yNodes,'LineWidth',0.5,'Color',[.5 .5 .5])
            end
            for d = (10:10:180)*rad
                xNodes = [cos(d) -cos(d)];
                yNodes = [sin(d) -sin(d)];
                plot(xNodes,yNodes,'LineWidth',0.5,'Color',[.5 .5 .5])
            end

            % X_c = phi_second * sqrt(sin(theta_second)) should be normally
            % distributed N(0, 1/FisherK). Test with KS.
            % ----------
            % Note that Fisher & Best, 1994, write N(0, 1/FisherK), buth this should
            % be an error, either in X_c or in the rotation, or a different
            % definition of FisherK, sice there is no way to accept this very
            % narrow distribution. Must be investigated.
            % ----------
            X_c = phi_second.*sqrt(sin(theta_second));

            % empirical cumulative distribution
            [~,X_c_ecdf] = ecdf(X_c);

            % create uniform distribution U(0, 2pi) with variance calculated from
            % transformed data X_c = phi_second * sqrt(sin(theta_second))
            normDist = makedist('Normal','mu',0,'sigma',std(X_c));
            normPDF = pdf(normDist,X_c_ecdf);

            % Kolmogorov-Smirnov test
            [normLHo,normLPval,~,~] = kstest(X_c,'CDF',normDist);
            disp(' ')
            disp('Kolmogorov-Smirnov GOF test for phi_second * sqrt(sin(theta_second)):')
            if normLHo == 0
                outcome = {'Normal dist. N(0, 1/K)';...
                    'ACCEPTED at 5% sign.';...
                    ['with P-value = ' num2str(normLPval)]};
            else
                outcome = {'Normal dist. N(0, 1/K)';...
                    'REJECTED at 5% sign.';...
                    ['with P-value = ' num2str(normLPval)]};
            end
            disp(outcome);

            % plot normal test
            axes(fig_2_7(i))
            hold off
            histogram(X_c,'Normalization','pdf','FaceColor',[.6 .6 .6]);
            hold on
            plot(X_c_ecdf,normPDF,'r','linewidth',2)
            grid on
            set(gca, 'PlotBoxAspectRatio', [1,2,1])
            title(outcome);

            % manage errors in Fisher test
        catch
            warning(['---- WARNING: Fisher test error for class ' num2str(class) ' ----'])
        end
    end

    disp(' ')
    disp('Fisher GOF tests done')

    % END FISHER STATISTICS

    % SUMMARY

    % reactivate subplot in figure 1 and plot cluster poles and means
    axes(fig_1_1)

    % clean plot if needed
    try
        for i = 1:length(clust_hand)
            delete(clust_hand(i))
        end
    end

    % plot means
    for i = 1:nClass
        class = keep_class(i);
        theta = (Dip(idClass==class))*rad;
        d = sqrt(2) * sin(theta/2);
        xNodes = d.* -sin((DipDirection(idClass==class))*rad);
        yNodes = d.* -cos((DipDirection(idClass==class))*rad);
        clust_hand(i*2-1) = plot(xNodes,yNodes,'ko','MarkerSize',3,'linewidth',1);
        meanTheta = (meanDip(i))*rad;
        d = sqrt(2) * sin(meanTheta/2);
        xMean = d.* -sin((meanDir(i))*rad);
        yMean = d.* -cos((meanDir(i))*rad);
        clust_hand(i*2) = plot(xMean,yMean,'kd','MarkerSize',6,'linewidth',2,'MarkerFaceColor','w');
    end

    % reactivate subplot in figure 1 and add text
    axes(fig_1_3)
    outcome = { ...
        ['                        Class ID = ' num2str(keep_class,'%12d')         ];...
        ['                  Poles in class = ' num2str(countClass,'%12d')         ];...
        ['                      % of total = ' num2str(countClassPercent,'%12.2f')];...
        ['                        Mean Dir = ' num2str(meanDir,'%12.2f')          ];...
        ['                        Mean Dip = ' num2str(meanDip,'%12.2f')          ];...
        ['                               K = ' num2str(fisherK,'%12.2f')          ];...
        ['            99% conf. cone angle = ' num2str(confC,'%12.2f')            ];...
        ['  68.26% variability sph. apert. = ' num2str(spherAp,'%12.2f')          ];...
        [''                                                                       ];...
        ['Max conc. % of total per 1% area = ' num2str(max_conc,'%12.2f')      ] ...
        };
    text(0,0.6,outcome','HorizontalAlignment','left','VerticalAlignment','top','FontName','Courier');

    % END SUMMARY

    disp(' ')
    disp('Done with clustering? [y]:')
    commandwindow
    done = input('>> ', 's');
    if isempty(done), done = 'y'; end
    if done == 'y', break; end
end

disp(' ')
disp('K-medoid clustering done')

% END K-MEDOID CLUSTERING

% SAVE

% save with class annotation
if inDataFormat == 1
    out_data = [DipDirection Dip idClass];
elseif inDataFormat == 2
    out_data = [Dip DipDirection idClass];
elseif inDataFormat == 3
    out_data = [Trend Plunge idClass];
elseif inDataFormat == 4
    out_data = [Plunge Trend idClass];
end

out_data = out_data(find(ismember(out_data(:,3),keep_class)),:);
csvwrite([filename '_classified.csv'],out_data)  % add header with column names?

disp(' ')
disp('output done')

end

% END SAVE

%% function rose_plot
% geologic rose plot inpired by earth_rose.m by Cameron Sparr
% in turn inspired by wind_rose.m
% The code to change the axis labels from a mathematical system to
% N,S,E,W were written by Jordan Rosenthal in a forum post:
% http://www.mathworks.com/matlabcentral/newsreader/author/4601
function rose_plot(strike, target_fig)

% focus to figure or subplot axes
axes(target_fig)

% strike (used by rose diagram only)
SymmetricStrike = [strike; (strike<=180).*(strike+180)+(strike>180).*(strike-180)];

% rose with bins at 10° increment
D = mod(90 - SymmetricStrike, 360)*pi/180;
rose(D, 36);
hHiddenText = findall(gca,'type','text');
Angles = 0 : 30 : 330;
hObjToDelete = zeros( length(Angles)-4, 1 );
k = 0;
for ang = Angles
    hObj = findall(hHiddenText,'string',num2str(ang));
    switch ang
        case 0
            set(hObj,'string','E','HorizontalAlignment','Left');
        case 90
            set(hObj,'string','N','VerticalAlignment','Bottom');
        case 180
            set(hObj,'string','W','HorizontalAlignment','Right');
        case 270
            set(hObj,'string','S','VerticalAlignment','Top');
        otherwise
            k = k + 1;
            hObjToDelete(k) = hObj;
    end
end
delete(hObjToDelete(hObjToDelete~=0));

end

%% function contour plot
% contour plot fron direction cosines, outputs % maximum concentration
function max_conc = contour_plot(Lpole, Mpole, Npole, target_fig)

% focus to figure or subplot axes
axes(target_fig)

% initialize
rad = pi/180;
deg = 180/pi;
cmap =[ones(1,10)' linspace(1,0,10)' linspace(1,0,10)'];
Ndata = length(Lpole);

% plunge/trend of grid node vectors for contouring grid by direct calculation
n = 1;
pNodes(n) = 90;
tNodes(n) = 0;
for i = 1:10
    m = 6*i;
    radius = i/10;
    DeltaPhi = 360/m;
    for j = 1:m
        phi = j*DeltaPhi;
        n = n+1;
        tNodes(n) = phi;
        theta = 2 * asin(radius/sqrt(2))*deg;
        pNodes(n) = 90 - theta;
    end
end

% direction cosines (l,m,n) of grid node vectors for contouring grid
for i = 1:331
    Lnodes(i) = cos(pNodes(i)*rad) * cos(tNodes(i)*rad);
    Mnodes(i) = cos(pNodes(i)*rad) * sin(tNodes(i)*rad);
    Nnodes(i) = -sin(pNodes(i)*rad);
end

% (x,y) coordinates of nodes for contouring grid from plunge/trend
for n = 1:331
    theta = (90-pNodes(n))*rad;
    d = sqrt(2) * sin(theta/2);
    xNodes(n) = d .* sin(tNodes(n)*rad);
    yNodes(n) = d .* cos(tNodes(n)*rad);
end
disp(' ')
disp('grid nodes done')

% define counting cone for contouring grid
% key = 2.0;
% cone = (acos(Ndata/(Ndata+key^2)))*deg;
% http://en.wikipedia.org/wiki/Solid_angle
cone = 8.1096144559941786958201832872484;

%count point density at all 331 nodes
for i = 1:331
    zNodes(i) = 0;
    %dot product of node vectors and data vectors
    for j = 1:Ndata
        theta = (acos(Lnodes(i)*Lpole(j) + Mnodes(i)*Mpole(j) + Nnodes(i)*Npole(j)))*deg;
        if theta <= cone
            zNodes(i) = zNodes(i)+1;
        end
    end
end
disp(' ')
disp('point density done')

%convert counts to percent
zNodes = zNodes/Ndata*100;
max_conc = max(zNodes);
disp(' ')
disp('density percent done')

% Kalsbeek contouring
% ------- CHECK THIS IF WE HAVE TIME --------
% set parameters:
% number of x and y nodes for grid
% make these smaller if you get an error about excceding the max array size
% nx = 50;
nx = 90;
ny = nx;
% number of contours:
ci = 5;
e=xNodes;
n=yNodes;
hh=zNodes;
%Grid the data linearly:
estep = abs((min(e)-max(e))/nx);
nstep = abs((min(n)-max(n))/ny);
ee = min(e):estep:max(e);
nn = min(n):nstep:max(n);
[xi,yi,zi] = griddata(e,n,hh,ee,nn');
% v = floor(min(hh)):ci:max(hh);
v = floor(linspace(min(hh),max(hh),ci));
disp(' ')
disp('gridding done')

% plotting

%draw primitive circle with standard radius = 1
xNodes = cos(linspace(0,2*pi,180));
yNodes = sin(linspace(0,2*pi,180));
plot(xNodes,yNodes,'k-')
hold on
axis equal
axis off
imagesc(ee',nn',zi)
colormap(cmap)
plot(xNodes,yNodes,'k-')
plot(0,0,'k+')
plot(1,0,'k+')
plot(0,1,'k+')
plot(-1,0,'k+')
plot(0,-1,'k+')
plot(0,0,'k+')

% contour
[c,h] = contour(xi,yi,zi,v,'-k');
clabel(c,h);

% plot polar grid
for d = sqrt(2) * sin((10:10:80)*rad/2)
    xNodes = d * cos(linspace(0,2*pi,180));
    yNodes = d * sin(linspace(0,2*pi,180));
    plot(xNodes,yNodes,'LineWidth',0.5,'Color',[.5 .5 .5])
end
for d = (10:10:180)*rad
    xNodes = [cos(d) -cos(d)];
    yNodes = [sin(d) -sin(d)];
    plot(xNodes,yNodes,'LineWidth',0.5,'Color',[.5 .5 .5])
end

end