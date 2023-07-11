function output = biaxial_decomp()
% Decomposes an input file for biaxial test into K2/K3 data.
% Note that all length parameters are in mm.
warning off

calc_xref = false;
change_inp = false;
run_abaqus = false;
read_dat = false;
calc_decomp = false;
calc_goodness = 'criscione'; % 'k_lam' or 'criscione'

R = 5.08; % Radius from center is 5.08mm
mask_shape = true; % Cut out a central piece of the biaxial specimen
parallel = false; % parfor loop for the decomposition (timing is the same)
bin_res = 0.01; % Bin resolution for histograms
maxLam = 2; % Maximum limit for lambda in plots
clim = [-5 -1.5]; % Colorbar limits for galaxy plots

fileName = 'Biaxial_Plus';

% Calculate x positions of nodes and elements
switch calc_xref
    case 1
        [X,Y,Z,ElNode] = readInp(fileName);
        output.X_ref.node = 25.4*[X,Y,Z]; % Nodal positions (mm)
        % Element centroidal positions
        for idx = 1:length(ElNode)
            for i = 1:8
                n(i) = ElNode(idx,i);
            end
            output.X_ref.el(idx,:) = 25.4*[mean(X(n(:))),mean(Y(n(:))),mean(Z(n(:)))]; % Convert to mm
        end
    case 0
        load('Data\23-0702-Biaxial-sim\refpositions.mat')
        output.X_ref = X_ref;
end

% Change history output requests for input file
if change_inp
        changeInp(fileName)
end

% Run abaqus simulation (22 minute simulation for hybrid elements)
if run_abaqus
    system(['abaqus job=' fileName '_test interactive cpus=4']);
    movefile([fileName '_test.dat'],'Data\AbaqusFiles','f');
    movefile([fileName '_test.odb'],'Data\AbaqusFiles','f');
    fclose('all');
    movefile([fileName '_test.inp'],'Data\AbaqusFiles','f');
    delete *_test.*
end

% Read DAT file
switch read_dat
    case 1
        addpath(genpath('Data'))
        [U,F] = readDat(['Data/AbaqusFiles/' fileName],length(output.X_ref.node));
        output.U_t{1} = 25.4*U; output.F_t{1} = F;
    case 0
        load('Data\23-0702-Biaxial-sim\MRI-3Ddefs_Biaxial_23-0702.mat')
        output.U_t = U_t; output.F_t = F_t;
end

% Modify U and F such that it's only data within a 0.4in cicrcle
if mask_shape
    x_center = mean([max(output.X_ref.node(:,1)) min(output.X_ref.node(:,1))]);
    z_center = mean([max(output.X_ref.node(:,3)) min(output.X_ref.node(:,3))]);
    j = 1;
    for i = 1:length(output.X_ref.node)
        if sqrt((output.X_ref.node(i,1)-x_center)^2+(output.X_ref.node(i,3)-z_center)^2)<R
            U_t_temp{1}(j,:) = output.U_t{1}(i,:);
            X_ref_node_temp(j,:) = output.X_ref.node(i,:);
            j = j + 1;
        end
    end
    output.U_t{1} = U_t_temp{1};
    output.X_ref.node = X_ref_node_temp;
    j = 1;
    for i = 1:length(output.X_ref.el)
        if sqrt(((output.X_ref.el(i,1)-x_center)^2)+((output.X_ref.el(i,3)-z_center)^2))<R
            for k = 1:3
                for l = 1:3
                    F_t_temp{1}{k,l}(j) = output.F_t{1}{k,l}(i);
                    X_ref_el_temp(j,:) = output.X_ref.el(i,:);
                end
            end
            j = j+1;
        end
    end
    output.F_t{1} = F_t_temp{1};
    output.X_ref.el = X_ref_el_temp;
end

% Def grad storage (1 - Biaxial sim; 2 - Biaxial exp; 3 - Uniaxial sim (7mm); 4 - Uniaxial exp (7mm)
output.lbl{1} = 'Biaxial_{sim} (4.5mm)'; output.lbl{2} = 'Biaxial_{exp} (4.5mm)';
output.lbl{3} = 'Uniaxial_{sim} (7mm)'; output.lbl{4} = 'Uniaxial_{exp} (7mm)';

load('Data/23-0627-Biaxial-exp/disp_data_20230627-eco_biaxial.mat');
if mask_shape
    load('Data/23-0627-Biaxial-exp/mask_data_900.mat')
    for i = 1:3
        for j = 1:3
            F_t_temp{2}{i,j} = F_t{1}{i,j}.*mask;
        end
    end
else
    F_t_temp{1} = output.F_t{1};
    F_t_temp{2} = F_t{1};
end
load('Data/22-0325-Uniaxial-sim/MRI-3Ddefs_SimpleShear_22-0325-Uniaxial.mat')
F_t_temp{3} = F_t{1};
load('Data/22-0325-Uniaxial-exp/MRI-3Ddefs_RectPrism_190919_222hfilt.mat')
F_t_temp{4} = F_t{10};
output.F_t = F_t_temp;

switch calc_decomp
    case 1
        % Decomposition for all 4 tests (k_lam - 15 sec; k2_k3 - 11 sec)
        [k,lam,~] = param_decoup_main(output.F_t,parallel,'ftolamandk');
        [k3,k2,~] = param_decoup_main(output.F_t,parallel,'ftok2andk3');
        if mask_shape
            save('Data/sensitivity_disc.mat','k','lam','k2','k3');
        else
            save('Data/sensitivity_full.mat','k','lam','k2','k3');
        end
        output.k = k; output.lam = lam; output.k2 = k2; output.k3 = k3;
    case 0
        if mask_shape
            load('Data/sensitivity_disc.mat')
        else
            load('Data/sensitivity_full.mat')
        end
        output.k = k; output.lam = lam; output.k2 = k2; output.k3 = k3;
end

mu = 1; % Normalizing mu
alpha = linspace(-5,5,1001);

switch calc_goodness
    case 'k_lam'
        % Sensitivity and goodness metric calcs (k and lambda)
        lambda = 1:bin_res:maxLam;
        k_=0:bin_res:1;
        
        Salpha_gen = @(k) mu*bsxfun(@times,log(lambda'),((-k^2+1.5*k+0.5)^2*bsxfun(@power,lambda',(-k^2+1.5*k+0.5)*alpha-1)...
            +(-k+0.5)^2*bsxfun(@power,lambda',(-k+0.5)*alpha-1)...
            +(k^2-0.5*k-1)^2*bsxfun(@power,lambda',(k^2-0.5*k-1)*alpha-1)));
        Smu_gen = @(k) (-k^2+1.5*k+0.5)*bsxfun(@power,lambda',(-k^2+1.5*k+0.5)*alpha-1)...
            +(-k+0.5)*bsxfun(@power,lambda',(-k+0.5)*alpha-1)...
            +(k^2-0.5*k-1)*bsxfun(@power,lambda',(k^2-0.5*k-1)*alpha-1);
        
        for i = 1:length(k_)
            Salpha_all(:,:,i) = Salpha_gen(k_(i));
            Smu_all(:,:,i) = Smu_gen(k_(i));
        end
        output.Salpha_all = Salpha_all;
        output.Smu_all = Smu_all;
        
        for i = 1:length(output.k)
            figure()
            [~,~,h] = ndhist(output.lam{i}(:),output.k{i}(:),'axis',[1,0;maxLam,1],'fixed_bin_res',bin_res);
            output.H{i} = h';
            imagesc([1 maxLam],[0 1],log10(h/sum(h(:))));
            axis square
            colormap turbo;
            set(gca,'YDir','normal'); 
            ylabel('k, Stretch state','interpreter','latex')
            xlabel('$\lambda$, Stretch amplitude','interpreter','latex')
            title(['K vs Lambda Decomposition $' output.lbl{i} '$'],'interpreter','latex')
            c = colorbar; caxis(clim);
            c.Label.String = 'log(h/sum(h(:)))';
            if i == 1
                if mask_shape
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_disc_k_lam.png'])
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_disc_k_lam.pdf'])
                else
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_fullsample_k_lam.png'])
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_fullsample_k_lam.pdf'])
                end
            elseif i ==2
                if mask_shape
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_disc_k_lam.png'])
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_disc_k_lam.pdf'])
                else
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_fullsample_k_lam.png'])
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_fullsample_k_lam.pdf'])
                end
            elseif i ==3
                saveas(gcf,['Data/22-0325-Uniaxial-sim/2Dhist_k_lam.png'])
                saveas(gcf,['Data/22-0325-Uniaxial-sim/2Dhist_k_lam.pdf'])
            elseif i ==4
                saveas(gcf,['Data/22-0325-Uniaxial-exp/2Dhist_k_lam.png'])
                saveas(gcf,['Data/22-0325-Uniaxial-exp/2Dhist_k_lam.pdf'])
            end
        end
        
        figure();
        for test = 1:length(output.k)
            for i = 1:length(alpha)
                mat_temp{i} = squeeze(Salpha_all(:,i,:));
                mat_temp2{i} = squeeze(Smu_all(:,i,:));
                % mat_temp{i} = mat_temp{i}./sum(mat_temp{i}(:)); % Normalized
                S_lookup{test}(i,1) = alpha(i);
                S_lookup{test}(i,2) = sum(output.H{test}(:).*mat_temp{i}(:));
                S_lookup{test}(i,3) = sum(output.H{test}(:).*mat_temp2{i}(:));
            end
            if test == length(output.k)
                S_hat_lookup = S_lookup;
                for j = 1:length(output.k)
                    nrmlz(j) = sum(output.H{j}(:));
                    S_hat_lookup{j}(:,2) = S_lookup{j}(:,2)/sum(output.H{j}(:)); % Normalized
                    S_hat_lookup{j}(:,3) = S_lookup{j}(:,3)/sum(output.H{j}(:)); % Normalized
                    if rem(j,2) == 0
                        plot(S_hat_lookup{j}(:,1),S_hat_lookup{j}(:,2),'Color',[j/length(output.k) 0 0],'LineWidth',2)
                    else
                        plot(S_hat_lookup{j}(:,1),S_hat_lookup{j}(:,2),'--','Color',[j/length(output.k) 0 0],'LineWidth',2)
                    end
                    hold on
                end
            end
        end
        title('$S_{metric}$(test,$\alpha$)','interpreter','latex')
        xlabel('$\alpha$','interpreter','latex')
        ylabel('$S_{metric}=\sum_{i,j}\hat{hist}\left(k_i,\lambda_j,test\right)\;.*\;\hat{S}_\alpha\left(k_i,\lambda_j,\alpha\right)$',...
            'interpreter','latex')
        legend(output.lbl{1},output.lbl{2},output.lbl{3},output.lbl{4},'interpreter','latex')
        if mask_shape
            saveas(gcf,'Data/goodness_metric_k_lam_disc.png')
            saveas(gcf,'Data/goodness_metric_k_lam_disc.pdf')
        else
            saveas(gcf,'Data/goodness_metric_k_lam_fullsample.png')
            saveas(gcf,'Data/goodness_metric_k_lam_fullsample.pdf')
        end

    case 'criscione'
        % Sensitivity and goodness metric calcs (k2 and k3)
        k_2 = 0:bin_res:floor(log(maxLam)/sqrt(2/3)/bin_res)*bin_res;
        k_3=-1:2*bin_res:1;
        
        g1 = @(k_3) sqrt(2/3)*sin(-asin(k_3)/3+(2*pi/3));
        g2 = @(k_3) sqrt(2/3)*sin(-asin(k_3)/3);
        g3 = @(k_3) sqrt(2/3)*sin(-asin(k_3)/3-(2*pi/3));
        
        Smu_gen = @(k_3) g1(k_3)*exp(g1(k_3)*bsxfun(@times,alpha,k_2')) + ...
            g2(k_3)*exp(g2(k_3)*bsxfun(@times,alpha,k_2')) + ...
            g3(k_3)*exp(g3(k_3)*bsxfun(@times,alpha,k_2'));
        Salpha_gen = @(k_3) mu*((g1(k_3)^2)*bsxfun(@times,k_2',exp(g1(k_3)*...
            bsxfun(@times,alpha,k_2'))) + (g2(k_3)^2)*bsxfun(@times,k_2',...
            exp(g2(k_3)*bsxfun(@times,alpha,k_2'))) + (g3(k_3)^2)*bsxfun(@times,...
            k_2',exp(g3(k_3)*bsxfun(@times,alpha,k_2'))));
        
        for i = 1:length(k_3)
            Salpha_all(:,:,i) = Salpha_gen(k_3(i));
            Smu_all(:,:,i) = Smu_gen(k_3(i));
        end
        output.Salpha_all = Salpha_all;
        output.Smu_all = Smu_all;

        for i = 1:length(output.k3)
            figure()
            [~,~,h] = ndhist(output.k2{i}(:),output.k3{i}(:),'axis',[min(k_2) max(k_2) min(k_3) max(k_3)],'fixed_bin_res',bin_res,'scale_y',2);
            output.H{i} = h';
            imagesc([min(k_2) max(k_2)],[min(k_3) max(k_3)],log10(h/sum(h(:))));
            axis square
            colormap turbo;
            set(gca,'YDir','normal'); 
            ylabel('$k_3$, Strain state','interpreter','latex')
            xlabel('$k_2$, Log strain amplitude','interpreter','latex')
            title(['k2 vs k3 Decomposition $' output.lbl{i} '$'],'interpreter','latex')
            c = colorbar; caxis(clim);
            c.Label.String = 'log(h/sum(h(:)))';
            if i == 1
                if mask_shape
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_disc_k2_k3.png'])
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_disc_k2_k3.pdf'])
                else
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_fullsample_k2_k3.png'])
                    saveas(gcf,['Data/23-0702-Biaxial-sim/2Dhist_fullsample_k2_k3.pdf'])
                end
            elseif i ==2
                if mask_shape
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_disc_k2_k3.png'])
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_disc_k2_k3.pdf'])
                else
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_fullsample_k2_k3.png'])
                    saveas(gcf,['Data/23-0627-Biaxial-exp/2Dhist_fullsample_k2_k3.pdf'])
                end
            elseif i ==3
                saveas(gcf,['Data/22-0325-Uniaxial-sim/2Dhist_k2_k3.png'])
                saveas(gcf,['Data/22-0325-Uniaxial-sim/2Dhist_k2_k3.pdf'])
            elseif i ==4
                saveas(gcf,['Data/22-0325-Uniaxial-exp/2Dhist_k2_k3.png'])
                saveas(gcf,['Data/22-0325-Uniaxial-exp/2Dhist_k2_k3.pdf'])
            end
        end

        figure();
        for test = 1:length(output.k3)
            for i = 1:length(alpha)
                mat_temp{i} = squeeze(Salpha_all(:,i,:));
                mat_temp2{i} = squeeze(Smu_all(:,i,:));
                % mat_temp{i} = mat_temp{i}./sum(mat_temp{i}(:)); % Normalized
                S_lookup{test}(i,1) = alpha(i);
                S_lookup{test}(i,2) = sum(output.H{test}(:).*mat_temp{i}(:));
                S_lookup{test}(i,3) = sum(output.H{test}(:).*mat_temp2{i}(:));
            end
            if test == length(output.k3)
                S_hat_lookup = S_lookup;
                for j = 1:length(output.k3)
                    nrmlz(j) = sum(output.H{j}(:));
                    S_hat_lookup{j}(:,2) = S_lookup{j}(:,2)/sum(output.H{j}(:)); % Normalized
                    S_hat_lookup{j}(:,3) = S_lookup{j}(:,3)/sum(output.H{j}(:)); % Normalized
                    if rem(j,2) == 0
                        plot(S_hat_lookup{j}(:,1),S_hat_lookup{j}(:,2),'Color',[j/length(output.k) 0 0],'LineWidth',2)
                    else
                        plot(S_hat_lookup{j}(:,1),S_hat_lookup{j}(:,2),'--','Color',[j/length(output.k) 0 0],'LineWidth',2)
                    end
                    hold on
                end
            end
        end
        title('$S_{metric}$(test,$\alpha$)','interpreter','latex')
        xlabel('$\alpha$','interpreter','latex')
        ylabel('$S_{metric}=\sum_{i,j}\hat{hist}\left(k_i,\lambda_j,test\right)\;.*\;\hat{S}_\alpha\left(k_i,\lambda_j,\alpha\right)$',...
            'interpreter','latex')
        legend(output.lbl{1},output.lbl{2},output.lbl{3},output.lbl{4},'interpreter','latex')
        if mask_shape
            saveas(gcf,'Data/goodness_metric_k2_k3_disc.png')
            saveas(gcf,'Data/goodness_metric_k2_k3_disc.pdf')
        else
            saveas(gcf,'Data/goodness_metric_k2_k3_fullsample.png')
            saveas(gcf,'Data/goodness_metric_k2_k3_fullsample.pdf')
        end
end