function stream = score(varargin)
    % Enter a string that specifies what you want to do by using UNIXy pipeline notation.
    % Usage:
    % >> score('load RECORD | FILTER ARG ... ARG | ... | FILTER ARG ... ARG')
    % or
    % >> score(STREAM, 'FILTER ARG ... ARG | ... | FILTER ARG ... ARG')
    %
    % Example 1:
    % >> score('load shh | segment 3 | extract | select Mean Variance | bundle 12RW 34M | partition 0.25 | svm linear | eval | plot')
    % Or, alternatively:
    % >> vectors = score('load shh | segment 3 | extract | select Mean Variance')
    % >> score(vectors,'bundle 12RW 34M | partition 0.25 | svm linear | eval | plot')
    % This does the following:
    % 1. The signal and labels of the SHHS record are read from the record file.
    % 2. The signal is segmented into 3 segments per epoch (i.e. 10 second segments).
    % 3. A feature vector is extracted from each segment.
    % 4. All features in the feature vector except Mean and Variance are stripped away.
    % 5. Labels 1, 2, R and W are bundled into label A; labels 3, 4, M are bundled into B.
    % 6. Randomly selects 25 % of the vectors as training vectors; the rest become test vectors.
    % 7. Constructs an SVM classifier from the training set.
    % 8. Evaluates the accuracy of the SVM classifier.
    % 9. Plots the mismatch between the test set and predicted set.
    %
    % Filters:
    % load RECORD
    %     Loads the signal and annotations from the record RECORD. Entering only a substring of the
    %     name of the record as RECORD is fine, as long as there is no ambiguity (e.g. "shhs" as a
    %     shorthand for "shhs1-200001").
    %     Output: 1x1 Signal.
    % segment COUNT
    %     Input: Signal instance.
    %     Divides a signal into COUNT segments per annotation.
    %     Output: Nx1 Segment.
    % extract
    %     Input: Nx1 Segment.
    %     Extracts a vector of features from each segment.
    %     Output: Nx1 Featurevector.
    % select FEATURE ... FEATURE
    %     Input: Nx1 Featurevector.
    %     Strips away all features in the feature vector except those specified.
    %     Output: Nx1 Featurevector.
    % select exhaustive CLASSIFIER
    %     Input: Partition.
    %     Applies classifier CLASSIFIER to the input partition for every combination of features.
    %     Output: Mx1 struct array with fields trainingset, testingset, svm, predictedset, accuracy.
    % select restricted CLASSIFIER
    %     Input: Partition.
    %     Uses restricted search with GA and classifier CLASSIFIER to find the best combinations of
    %     features for the input partition.
    %     Output: Mx1 struct array with fields trainingset, testingset, svm, predictedset, accuracy.
    % keep RATIO
    %     Input: Nx1 Featurevector.
    %     Randomly discards 1-RATIO of the feature vectors.
    %     Output: Mx1 Featurevector.
    % balance
    %     Input: Nx1 Featurevector.
    %     Makes the number of vectors belonging to a label constant.
    %     Output: Mx1 Featurevector.
    % pca
    %     Input: Nx1 Featurevector.
    %     Constructs a new, two-dimensional feature space from the feature space, in which the first
    %     and second components of each vector are the first and second principal components.
    %     Output: Nx1 Featurevector.
    % bundle LABELS ... LABELS
    %     Input: Nx1 LabeledFeaturevector.
    %     Bundles every label (character) in the first LABELS into the new label A, every label in
    %     the second LABELS into B, and so on.
    %     Output: Nx1 LabeledFeaturevector.
    % partition RATIO
    %     Input: Nx1 LabeledFeaturevector.
    %     Randomly partitions RATIO of the feature space into a training set and the rest into a test set.
    %     Output: 1x1 struct with fields trainingset, testingset.
    % svm KERNEL
    %     Input: 1x1 struct with fields trainingset, testingset. KERNEL is either "linear" or "rbf"
    %     Constructs an SVM classifier from the training set.
    %     Output: 1x1 struct with fields trainingset, testingset, svm.
    % eval
    %     Input: 1x1 struct with fields trainingset, testingset, svm.
    %     Evaluates the accuracy of the classifier.
    %     Output: 1x1 struct with fields trainingset, testingset, svm, predictedset, accuracy.
    % organize cluster K
    %     Input: Nx1 Featurevector, or a partition.
    %     Performs (unsupervised) hard k-means clustering on the feature space. Extends the feature
    %     space with another feature which is an integer in [1,K] and signifies the cluster of the
    %     vector.
    %     Output: Nx1 Featurevector, or a partition.
    % plot
    %     Input: Nx1 LabeledFeaturevector, or partition, or evaluation.
    %     Plots the stream in a way that depends on what it consists of.
    % plot clusters
    %     Input: Nx1 LabeledFeaturevector in which Cluster is a feature.
    %     If the stream is a clustered feature space, this plots the clusters.
    % plot hypnogram
    %     Input: Nx1 LabeledFeaturevector, or a struct with testingset and predictedset fields.
    %     Plots the hypnogram or the two hypnograms.
    if nargin == 0
        error('Expected at least one argument. Type "help score" for usage.')
    elseif nargin == 1
        cmd = varargin{1};
    elseif nargin == 2
        stream = varargin{1};
        cmd = varargin{2};
    end
    pipeline = strsplit(cmd,'|');
    for filter = pipeline
        tokens = strsplit(strtrim(filter{:}));
        if strcmp(tokens{1},'load')
            recordstr = tokens{2};
            [record,eeg,labels] = readrecord(recordstr);
            stream = struct('eeg',eeg,'labels',labels);
        elseif strcmp(tokens{1},'segment')
            segmentsperannotation = str2num(tokens{2});
            seconds = 30/segmentsperannotation;
            segments = stream.eeg.segment(seconds);
            labels = repmat(stream.labels',segmentsperannotation,1);
            labels = labels(:);
            labeledsegments = arrayfun(@(i){segments(i).label(labels(i))},(1:size(segments,1)));
            labeledsegments = [labeledsegments{:}]';
            stream = labeledsegments;
        elseif strcmp(tokens{1},'extract')
            fs = arrayfun(@(s){s.features},stream);
            fs = [fs{:}]';
            stream = fs;
        elseif strcmp(tokens{1},'select')
            if size(tokens,2) == 4
                classifier = tokens{3};
                kernel = tokens{4};
                if strcmp(tokens{2},'exhaustive')
                    allfeatures = stream.trainingset.features;
                    selections = [];
                    for i = 1:numel(allfeatures)
                        selections = [selections;num2cell(nchoosek(allfeatures,i),2)];
                    end
                    vpartitions = [];
                    for selection = selections'
                        sel = selection{:};
                        disp(['Selection: ',strjoin(sel)])
                        vps = score(stream.trainingset,'partition 5 fold');
                        for i = 1:numel(vps)
                            vps(i).trainingset = vps(i).trainingset.select(sel{:});
                            vps(i).testingset = vps(i).testingset.select(sel{:});
                        end
                        evals = arrayfun(@(p)score(p,[classifier,' ',kernel,' | eval']),vps);
                        accuracies = arrayfun(@(e)e.accuracy,evals);
                        medianindex = find(accuracies == median(accuracies));
                        medianindex = medianindex(1);  % Two accuracies are sometimes the same
                        vpartitions = [vpartitions;evals(medianindex)];
                    end
                    stream.evaluation = vpartitions;
                    stream = rmfield(stream,'trainingset');
                elseif strcmp(tokens{2},'restricted')
                    stream.evaluation = restrictedsearch(stream.trainingset,classifier,kernel);
                    stream = rmfield(stream,'trainingset');
                end
            else
                features = tokens(2:end);
                if isa(stream,'LabeledFeaturevector')
                    stream = stream.select(features{:});
                elseif isfield(stream,'trainingset')
                    newstream = struct();
                    newstream.trainingset = stream.trainingset.select(features{:});
                    newstream.testingset = stream.testingset.select(features{:});
                    stream = newstream;
                end
            end
        elseif strcmp(tokens{1},'partition')
            if numel(tokens) >= 3 && strcmp(tokens{3},'fold')
                foldcount = str2num(tokens{2});
                foldindices = crossvalind('Kfold',numel(stream),foldcount);
                folds = [];
                for i = 1:foldcount
                    trainingset = stream(find(foldindices~=i));
                    validationset = stream(find(foldindices==i));
                    folds = [struct('trainingset',trainingset,'testingset',validationset),folds];
                end
                stream = folds;
            else
                [numerator,denominator] = str2fraction(tokens{2});
                trainingindices = randperm(size(stream,1),round(numerator/denominator*size(stream,1)))';
                testindices = setdiff(1:size(stream,1),trainingindices)';
                trainedfs = stream(trainingindices);
                testedfs = stream(testindices);
                stream = struct('trainingset',trainedfs,'testingset',testedfs);
            end
        elseif strcmp(tokens{1},'bundle')
            bundles = tokens(2:end);
            newlabel = 'A';
            for bundle = bundles
                indices = ismember([stream.Label],bundle{:})';
                newlabels = num2cell(repmat(newlabel,1,size(indices,1)));
                [stream(indices).Label] = newlabels{:};
                newlabel = char(newlabel+1);
            end
        elseif strcmp(tokens{1},'keep')
            [numerator,denominator] = str2fraction(tokens{2});
            indices = randperm(size(stream,1),numerator/denominator*size(stream,1));
            stream = stream(indices);
        elseif strcmp(tokens{1},'balance')
            if isa(stream,'LabeledFeaturevector')
                partition = stream.partition();
                cardinality = min(cellfun(@(p)(size(p,2)),partition.values));
                newstream = [];
                for part = partition.values
                    indices = randperm(size(part{:},2),cardinality);
                    newpart = part{:};
                    newpart = newpart(indices);
                    newstream = [newpart,newstream];
                end
                stream = newstream';
            elseif isfield(stream,'trainingset')
                partition = stream.trainingset.partition();
                cardinality = min(cellfun(@(p)(size(p,2)),partition.values));
                newset = [];
                for part = partition.values
                    indices = randperm(size(part{:},2),cardinality);
                    newpart = part{:};
                    newpart = newpart(indices);
                    newset = [newpart,newset];
                end
                stream.trainingset = newset';
            end
        elseif strcmp(tokens{1},'organize')
            if strcmp(tokens{2},'dbn')
                layersizes = cellfun(@(s)str2num(s),tokens(3:end));
                if isa(stream,'LabeledFeaturevector')
                    stream = dbnify(stream,layersizes);
                elseif isfield(stream,'trainingset')
                    newstream = struct();
                    newstream.trainingset = score(stream.trainingset,filter{:});
                    newstream.testingset = score(stream.testingset,filter{:});
                    stream = newstream;
                end
            elseif strcmp(tokens{2},'cluster')
                k = str2num(tokens{3});
                if isa(stream,'LabeledFeaturevector')
                    stream = stream.kmeans(k);
                elseif isfield(stream,'trainingset')
                    newstream = struct();
                    newstream.trainingset = score(stream.trainingset,filter{:});
                    newstream.testingset = score(stream.testingset,filter{:});
                    stream = newstream;
                end
            end
        elseif strcmp(tokens{1},'pca')
            stream = stream.pca(2);
        elseif strcmp(tokens{1},'plot')
            figure
            whitebg(1,'w')
            hold on
            if numel(tokens) >= 2 && strcmp(tokens{2},'hypnogram')
                if isa(stream,'LabeledFeaturevector')
                    plothypnogram(stream)
                elseif isfield(stream,'testingset') && isfield(stream,'predictedset')
                    plothypnogram(stream.testingset)
                    plothypnogram(stream.predictedset)
                end
            end
            if numel(tokens) >= 2 && strcmp(tokens{2},'bar')
                if numel(tokens) >= 3 && strcmp(tokens{3},'mitzvah')
                    featurecount = ceil(log2(numel(stream.evaluation)));
                    bars = {};
                    ctr = 1;
                    for i = 1:featurecount
                        bars = {bars{:},[stream.evaluation(ctr:ctr+nchoosek(featurecount,i)-1).accuracy]};
                        ctr = ctr + nchoosek(featurecount,i);
                    end
                    bars = cell2mat(arrayfun(@(b){[mean(b{:});max(b{:})]},bars))';
                    bar(bars)
                    title('Average accuracy for different feature selections')
                    xlabel('Number of features in selection')
                    ylabel('Accuracy')
                else
                    bar([stream.evaluation.accuracy]')
                end
            elseif isfield(stream,'svm')
                stream.svm.plot()
            end
            if (numel(tokens) == 1 || ~strcmp(tokens{2},'hypnogram')) && isa(stream,'LabeledFeaturevector')
                vs = [stream.Vector]';
                features = fieldnames(vs);
                xaxis = [vs.(features{1})]';
                yaxis = [vs.(features{2})]';
                labels = [stream.Label]';
                if size(tokens,2) == 2
                    if strcmp(tokens{2},'clusters')
                        clusterindex = find(strcmp(features,'Cluster'));
                        m = stream.matrix;
                        for i = 1:max(m(:,clusterindex))
                            indices = find(m(:,clusterindex)==i);
                            style = [rand,rand,rand];
                            style = [1 1 1] - style/sum(style)/5;
                            plot(stream(indices),{style,'.',80,'off'})
                        end
                    end
                end
                plot(stream,{})
            elseif numel(stream) == 1 && isfield(stream,'trainingset') && isfield(stream,'testingset')
                plot(stream.trainingset,{'','*','','off'})
                plot(stream.testingset,{'','.','','off'})
                if isfield(stream,'predictedset')
                    pfs = stream.predictedset;
                    pfs = arrayfun(@(i){LabeledFeaturevector(pfs(i).Vector,pfs(i).Label)},(1:size(pfs,1)));
                    pfs = [pfs{:}]';
                    diff = [pfs.Label]'-[stream.testingset.Label]';
                    indices = find(diff);
                    pfs = pfs(indices);
                    plot(pfs,{[0.25 0 0.5],'o',8,'off'})
                end
            end
        elseif strcmp(tokens{1},'svm')
            stream.svm = SVM(stream.trainingset,tokens{2});
        elseif strcmp(tokens{1},'eval')
            if isfield(stream,'svm')
                stream.predictedset = stream.svm.predict(stream.testingset);
                plabels = [stream.predictedset.Label]';
                tlabels = [stream.testingset.Label]';
                diff = plabels-tlabels;
                diff(diff~=0) = 1;
                stream.accuracy = 1-sum(diff)/size(diff,1);
                m = [tlabels,plabels];
                [~,arrangement] = sort(m(:,1));
                tlabels = m(arrangement,1);
                plabels = m(arrangement,2);
                [confmat,order] = confusionmat(tlabels,plabels);
                stream.confusionmatrix = confmat;
                stream.confusionorder = order;
            elseif numel(stream) > 1
                stream = stream(1);
            else  % test set + validationevaluations -> trueevaluations
                evaluation = stream.evaluation;
                newevaluations = [];
                for e = evaluation'
                    newe = struct();
                    newe.svm = e.svm;
                    optimalselection = e.trainingset.features;
                    newe.testingset = stream.testingset;
                    newe.trainingset = e.trainingset;
                    newe.validationset = e.testingset;
                    newe.testingset = stream.testingset.select(optimalselection{:});
                    newe.validationconfusionmatrix = e.confusionmatrix;
                    newe.validationconfusionorder = e.confusionorder;
                    newe = score(newe,'eval');
                    newevaluations = [newevaluations;newe];
                end
                [~,indices] = sort([newevaluations.accuracy]);
                newevaluations = flip(newevaluations(indices));
                stream = newevaluations;
            end
        else
            error(['Could not interpret command "',tokens{1},'".'])
        end
    end
end

function stream = restrictedsearch(trainingset,classifier,kernel)
    decoder = {trainingset,classifier,kernel};
    [~,stream] = my_ga(trainingset.dimension,5,0.2,5,decoder);
end

function [fittest,evaluation] = my_ga(dimensions,N,mutationrate,runs,decoder)
    generation = round(rand(N,dimensions));
    disp(['Computing generation 1/',num2str(runs),'...'])
    generation = nonzeroize(generation);
    evaluations = fitness(generation,decoder);
    [~,argmax] = max([evaluations.accuracy]);

    for t = 2:runs
        [generation,[evaluations.accuracy]']
        disp(['Computing generation ',num2str(t),'/',num2str(runs),'...'])
        offspring = zeros(N,dimensions)-1;
        for row = 1:N
            % Selection
            y = cumsum([evaluations.accuracy]');
            x1 = rand*sum([evaluations.accuracy]');
            index1 = find(x1 < y,1);
            index2 = index1;
            while index2 == index1
                x2 = rand*sum([evaluations.accuracy]');
                index2 = find(x2 < y,1);
            end
            % Crossing
            crossindex = ceil(rand*dimensions);
            offspring(row,:) = [generation(index1,1:crossindex-1),generation(index2,crossindex:dimensions)];
            disp(['Cross rows ',num2str(index1),' and ',num2str(index2),' at ',num2str(crossindex)])
            % Mutation
            mutation = rand(1,dimensions) < mutationrate;
            offspring(row,:) = xor(offspring(row,:),mutation);
            offspring = nonzeroize(offspring);
            % Update fitnesses
            offspringevaluations(row,:) = fitness(offspring(row,:),decoder);
        end
        % Elitism
        allevaluations = [evaluations;offspringevaluations];
        allindividuals = [generation;offspring];
        [sorted,sortindices] = sort([allevaluations.accuracy]');
        sorted = flip(sorted);
        sortindices = flip(sortindices);
        generation = allindividuals(sortindices(1:N),:);
        evaluations = allevaluations(sortindices(1:N),:);
    end
    %[generation,[evaluations.accuracy]']
    [~,argmax] = max([evaluations.accuracy]);
    fittest = generation(argmax,:);
    evaluation = evaluations(argmax,:);
end

function newrows = nonzeroize(rows)
    % If there is a row with sum = 0, set it to a random nonzero binary vector.
    newrows = rows;
    indices = find(sum(rows,2)==0);
    if isempty(indices)
        newrows = rows;
    else
        for i = indices
            newrows(i,:) = round(rand(1,size(rows,2)));
        end
        newrows = nonzeroize(newrows);
    end
end

function evaluations = fitness(encodings,decoder)
    evaluations = [];
    trainingset = decoder{1};
    classifier = decoder{2};
    kernel = decoder{3};
    allfeatures = trainingset.features;
    for row = 1:size(encodings,1)
        encoding = encodings(row,:);
        if sum(encoding) == 0  % Cannot select zero features
            error('Selected zero features!')
        else
            selectedfeatures = allfeatures(find(encoding));
            newfeaturespace = trainingset.select(selectedfeatures{:});
            vps = score(newfeaturespace,'partition 5 fold');  %TODO soft-code
            evals = arrayfun(@(p)score(p,[classifier,' ',kernel,' | eval']),vps);
            accuracies = arrayfun(@(e)e.accuracy,evals);
            medianindex = find(accuracies == median(accuracies));
            medianindex = medianindex(1);  % Two accuracies are sometimes the same
            evaluations = [evaluations;evals(medianindex)];
        end
    end
end

function [numerator,denominator] = str2fraction(fracstr)
    parts = strsplit(fracstr,':');
    if size(parts,2) == 2
        numerator = str2num(parts{1});
        denominator = numerator+str2num(parts{2});
    else
        numerator = str2num(fracstr);
        denominator = 1;
    end
end

function plothypnogram(labeledfeatureset)
    labels = [labeledfeatureset.Label];
    labelset = unique(labels);
    ylim([0,numel(labelset)+1])
    set(gca,'yTick',0:numel(labelset)+1)
    set(gca,'yTickLabel',[{' '},num2cell(labelset),{' '}])
    numericlabels = arrayfun(@(x)(find(x==labelset)),labels);
    stairs(numericlabels,'Color',[rand,rand,rand])
end

function plot(labeledfeatureset,style)
    if isempty(labeledfeatureset)
        return
    end
    vs = [labeledfeatureset.Vector]';
    features = fieldnames(vs);
    plotdata = [[vs.(features{1})]',[vs.(features{2})]',double([labeledfeatureset.Label]')];
    plotdata = sortrows(plotdata,3);
    gscatter(plotdata(:,1),plotdata(:,2),char(plotdata(:,3)),style{:})
    xlabel(features{1})
    ylabel(features{2})
end

function [record,eeg,labels] = readrecord(spec)
    % Reads the record specified by the supplied parameter.
    datadir = 'data/';
    records = {
    'slp01a/slp01a',
    'shhs/shhs1-200001'
    'shhs/shhs1-200002'
    'shhs/shhs1-200003'
    'shhs/shhs1-200004'
    'shhs/shhs1-200005'
    'shhs/shhs1-200006'
    'shhs/shhs1-200007'
    'shhs/shhs1-200008'
    'shhs/shhs1-200009'
    'shhs/shhs1-200010'
    }; % TODO cache this data
    matches = strfind(records,spec);
    matchindices = find(cellfun(@(y)~isempty(y),matches));
    record = records{1};
    if length(matchindices) > 0
        record = records{matchindices(1)};
    else
        error(['Found no record that matches input "',spec,'".'])
    end
    cachepath = cachepath(record);
    if exist(cachepath)
        disp(['Reading ',cachepath,'...'])
        data = load(cachepath,'eeg','labels');
        eeg = data.eeg;
        labels = data.labels;
    else
        recordpath = [datadir,record];
        disp(['Reading ',recordpath,'...'])
        [eeg,labels] = readsignal(recordpath);
        save(cachepath,'eeg','labels');
    end
end

function path = cachepath(record)
    % Returns the path to the file caching the record.
    path = ['cache/',strrep(record,'/','.'),'.mat'];
end

function [eeg,labels] = readsignal(recordpath)
    % Reads the record from the file specified by the path.
    if findstr(recordpath,'slp01a')
        addpath('lib/wfdb-toolbox/mcode/')

        [tm,signal,Fs,siginfo] = rdmat(strcat(recordpath,'m'));
        physicaleeg = signal(:,3);

        eeg = Signal(tm',siginfo(3).Units,physicaleeg);

        [ann,type,subtype,chan,num,comments] = rdann(recordpath,'st');
        annotations = [char([comments{:}]),num2str(ann)];
        labels = char([comments{:}]');
        labels = labels(:,1);
    elseif findstr(recordpath,'shhs')
        addpath('lib')

        edfpath = strcat(recordpath,'.edf');
        [hea,record] = edfread(edfpath);
        eegindex = find(ismember(hea.label,'EEG'));
        physicaleeg = record(eegindex,:)';
        clear record
        unit = hea.units(eegindex);

        csvpath = [recordpath,'-staging.csv'];
        csv = csvread(csvpath,1);  % Read everything below row 1 (header)
        epochs = csv(:,1);
        epochlength = 30;  % Seconds
        annotations = csv(:,2);
        values_per_epoch = size(physicaleeg,1)/size(csv,1);
        labels = repmat('_',size(annotations,1),1);
        stagemap = {[0 'W'] [1 '1'] [2 '2'] [3 '3'] [4 '4'] [5 'R'] [6 'M'] [9 'X']};
        for row=stagemap
            key = row{1}(1); value = row{1}(2);
            labels(annotations==key) = value;
        end
        labels = randk2aasm(labels);
        tm = (0:epochlength/values_per_epoch:size(epochs,1)*epochlength);
        tm = tm(1:size(physicaleeg,1));
        eeg = Signal(tm',unit,physicaleeg);
    else
        error(['Cannot decide on a reading method for ',recordpath])
    end
end

function relabeling = randk2aasm(labels)
    relabeling = labels;
    relabeling(relabeling=='4') = '3';
end
