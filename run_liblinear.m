addpath liblinear/liblinear-1.93/matlab

% set pseudo random number generator
s = RandStream('mt19937ar','Seed',3085);
RandStream.setDefaultStream(s);

profile = 'stk5-183c';
n_tmpl = 800;
pool_profile = 'mean';

liblinear_param = '-s 2 -c 100 -B 1';
n_train = inf;
normalization = 'pca';
combine_fbank = 0;

fprintf(1, '------------------- Experiment Summary --------------------\n');
fprintf(1, 'Features: %s-%d-%s\n', profile, n_tmpl, pool_profile);
fprintf(1, '#Train: %d per class\n', n_train);
fprintf(1, 'Normalization: %s\n', normalization);
fprintf(1, 'Classifier: %s\n', liblinear_param);
fprintf(1, 'Combine filterbank: %d\n', combine_fbank);
fprintf(1, '-----------------------------------------------------------\n');

% load data
fprintf(1, 'loading data...\n');
%load data/fbank-invariance-features-bigarray-compact-debug.mat
load data/fbank-stack1.mat
%load(sprintf('data/fbank-invariance-features-bigarray-%s-%d-%s.mat', profile, n_tmpl, pool_profile));

if combine_fbank
    fprintf(1, 'combining with fbank feature...\n');
    fbank_data = load('data/fbank-invariance-features-bigarray-compact-debug.mat');
    features_tr = [features_tr fbank_data.features_tr];
    features_dev = [features_dev fbank_data.features_dev];
end

trainlab_mg = 1+floor((trainlab-1)/3);
devsetlab_mg = 1+floor((devsetlab-1)/3);

subset_idx = false(1,size(features_tr,1));
classes = unique(trainlab_mg);
for i=1:length(classes)
    idx_i = find(trainlab_mg == i);
    len = min([n_train, length(idx_i)]);
    rp = randperm(length(idx_i));
    subset_idx(idx_i(rp(1:len))) = true;
end
nor_features_tr = features_tr(subset_idx,:);
nor_features_dev = features_dev;
%save memory
clear features_tr

fprintf(1, 'normalizing features...\n');
if strcmp(normalization, 'whiten-spec') || strcmp(normalization, 'whiten-tiknov') || strcmp(normalization, 'pca')
    % PCA Whiten
    the_mean = mean(nor_features_tr);
    X = bsxfun(@minus, nor_features_tr, the_mean);
    [V, D] = eig(X'*X);
    D = diag(D);
    if strcmp(normalization, 'whiten-spec')
        D(D ~= 0) = 1 ./ sqrt(D(D ~= 0));
    elseif strcmp(normalization, 'whiten-tiknov')
        D = 1 ./ sqrt(1e-5 + D);
    elseif strcmp(normalization, 'pca')
        D(D ~= 0) = 1;
    end
    V = V(:,D~=0); D = D(D ~= 0);

    W = V*diag(D)*V';
    nor_features_tr = X*W;
    nor_features_dev = bsxfun(@minus, nor_features_dev, the_mean)*W;
elseif strcmp(normalization, 'none')
    % do nothing
else
    error('unknown normalization: %s', normalization);
end

nor_features_tr_sp = sparse(double(nor_features_tr));
nor_features_dev_sp = sparse(double(nor_features_dev));
% save memory
clear nor_features_tr nor_features_dev

fprintf(1, 'training....\n');
tic;
model = train(double(trainlab_mg(subset_idx))', nor_features_tr_sp, liblinear_param);
toc
fprintf(1, 'predicting....\n');
[I, acc] = predict(double(devsetlab_mg)', nor_features_dev_sp, model);
