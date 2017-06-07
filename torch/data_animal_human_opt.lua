
do  
    local data = torch.class('data_animal_human')

    function data:__init(args)
        self.file_path_horse=args.file_path_horse
        self.file_path_human=args.file_path_human
        self.limit=args.limit;
        self.humanImage=args.humanImage;
        self.augmentation=args.augmentation;
        self.batch_size=args.batch_size;
        self.mean_file=args.mean_file;
        self.std_file=args.std_file;
        self.vanilla_mean_file=args.vanilla_mean_file
        self.vanilla_std_file=args.vanilla_std_file
        self.soumith_locnet=args.soumith_locnet;
        self.soumith_mean_file=args.soumith_mean_file;
        self.optimize=args.optimize;

        if self.soumith_mean_file and self.soumith_locnet then
            local meanStd=torch.load(self.soumith_mean_file);
            self.soumith_std=meanStd.std;
            self.soumith_mean=meanStd.mean;
        end


        self.soumith=args.soumith;
        self.bgr=args.bgr;

        self.start_idx_horse=1;
        self.params={input_size={32,32},
                    mean={122,117,104},
                    imagenet_mean={122,117,104},
                    labels_shape={5,3},
                    angles={-10,-5,0,5,10}};

        if args.input_size then
            self.params.input_size=args.input_size
        end



        if self.mean_file and self.std_file then
            if self.soumith then
                local meanStd=torch.load(self.mean_file);
                -- print (meanStd);
                self.std_im=meanStd.std;
                self.mean_im=meanStd.mean;
            else
                self.mean_im=image.load(self.mean_file)*255;
                self.std_im=image.load(self.std_file)*255;
            end
        end 

        if self.vanilla_mean_file and self.vanilla_std_file then

            self.vanilla_mean_im=image.load(self.vanilla_mean_file)*255;
            self.vanilla_std_im=image.load(self.vanilla_std_file)*255;           
        end

        self.training_set_horse={};
        self.training_set_human={};
        
        self.lines_horse=self:readDataFile(self.file_path_horse);
        if self.humanImage then
            self.lines_human=self:readDataFile(self.file_path_human);
        -- ,self.humanImage);
        else
            self.lines_human=self:readDataFileNoIm(self.file_path_human);
        end
        assert (#self.lines_horse == #self.lines_human)
        
        if self.augmentation then
            -- print ('TRUE');
            self.lines_horse,self.lines_human=self:shuffleLines(self.lines_horse,self.lines_human);
        end

        -- print (#self.lines_horse,#self.lines_human);
        -- print (self.lines_human[1]);
        if self.limit~=nil then
            local lines_horse=self.lines_horse;
            self.lines_horse={};

            local lines_human=self.lines_human;
            self.lines_human={};
            
            for i=1,self.limit do
                self.lines_horse[#self.lines_horse+1]=lines_horse[i];
                self.lines_human[#self.lines_human+1]=lines_human[i];
            end
        end

        if self.optimize then
            print ('OPTIMIZING');

            if self.humanImage then            
                self.lines_human,self.training_images_human,self.training_labels_human,
                self.lines_horse,self.training_images_horse,self.training_labels_horse= self:loadTrainingImages();
                print (#self.lines_human);
                print (#self.lines_horse);
                print (self.training_images_human:size());
                print (self.training_labels_human:size());
                print (self.training_images_horse:size());
                print (self.training_labels_horse:size());
            else
                self.lines_human,self.training_labels_human,self.lines_horse,self.training_images_horse,self.training_labels_horse
                = self:loadTrainingImages();
                print (#self.lines_human);
                print (#self.lines_horse);
                print (self.training_images_horse:size());
                print (self.training_labels_horse:size());
            end
            
        end

        print (#self.lines_horse,#self.lines_human);
        -- print (self.lines_horse);
        -- print (self.lines_human)
    end

    function data:loadTrainingImages()
        local im_all_horse,im_all_human;
        assert (#self.lines_horse==#self.lines_human);
        local num_lines=#self.lines_horse;
        im_all_horse=torch.zeros(num_lines,3,self.params.input_size[1],self.params.input_size[2])
        if self.humanImage then
            im_all_human = torch.zeros(num_lines,3,self.params.input_size[1],self.params.input_size[2])
        end
        
        local labels_human = torch.zeros(num_lines,5,3);
        local lines_human={};

        local labels_horse = torch.zeros(num_lines,5,3);
        local lines_horse={};

        local curr_idx=0
        for line_idx=1,#self.lines_horse do
            local img_path_horse=self.lines_horse[line_idx][1];
            local label_horse=npy4th.loadnpy(self.lines_horse[line_idx][2]):double();

            local img_path_human=self.lines_human[line_idx][1];
            -- print (self.lines_human[line_idx]);
            local idx_lab;
            if self.humanImage then
                idx_lab = 2;
            else
                idx_lab = 1;
            end
            local label_human=npy4th.loadnpy(self.lines_human[line_idx][idx_lab]):double();
            
            local status_img_horse,img_horse=pcall(image.load,img_path_horse);
            local status_img_human,img_human;
            if self.humanImage then
                status_img_human,img_human=pcall(image.load,img_path_human);
            else
                status_img_human=true;
            end


            if status_img_horse and status_img_human then
                curr_idx=curr_idx+1;
                lines_horse[curr_idx]=self.lines_horse[line_idx]; 
                lines_human[curr_idx]=self.lines_human[line_idx];
                labels_human[curr_idx]=label_human;
                labels_horse[curr_idx]=label_horse;
                self:loadSingleImage(img_horse,im_all_horse,curr_idx)                
                if self.humanImage then
                    loadSingleImage(img_human,im_all_human,curr_idx)
                end
            end

        end
        if self.humanImage then
            return lines_human,im_all_human,labels_human,lines_horse,im_all_horse,labels_horse
        else
            return lines_human,labels_human,lines_horse,im_all_horse,labels_horse
        end
    end

    function data:loadSingleImage(img_face,im_all,curr_idx)

        if img_face:size()[1]==1 then
            img_face= torch.cat(img_face,img_face,1):cat(img_face,1)
        end

        if img_face:size(2)~=self.params.input_size[1] then 
            img_face = image.scale(img_face,self.params.input_size[1],self.params.input_size[2]);
        end
        im_all[curr_idx]=img_face;
        -- print (labels:size(),label_face)
        
        
    end


    function data:shuffleLines(lines,lines2)
        local x=lines;
        local len=#lines;
        local y=lines2;

        local shuffle = torch.randperm(len)
        
        local lines={};
        local lines2={};
        for idx=1,len do
            lines[idx]=x[shuffle[idx]];
            lines2[idx]=y[shuffle[idx]];
        end
        return lines,lines2;
    end

    function data:getTrainingData()
        local start_idx_horse_before = self.start_idx_horse

        self.training_set_horse.data=torch.zeros(self.batch_size,3,self.params.input_size[1]
            ,self.params.input_size[2]);
        self.training_set_horse.label=torch.zeros(self.batch_size,self.params.labels_shape[1],self.params.labels_shape[2]);

        if self.humanImage then
            self.training_set_human.data=self.training_set_horse.data:clone();
            self.training_set_human.label=self.training_set_horse.label:clone();
            self.start_idx_horse=self:addTrainingData(self.training_set_horse,self.training_set_human,self.batch_size,
            self.lines_horse,self.lines_human,self.start_idx_horse,self.params)
        else
            self.training_set_human.label=self.training_set_horse.label:clone();
            self.start_idx_horse=self:addTrainingDataNoIm(self.training_set_horse,self.training_set_human,self.batch_size,
            self.lines_horse,self.lines_human,self.start_idx_horse,self.params)    
        end
        
        if self.start_idx_horse<start_idx_horse_before and self.augmentation then
            print ('shuffling data'..self.start_idx_horse..' '..start_idx_horse_before )
            if not self.optimize then
                self.lines_horse,self.lines_human=self:shuffleLines(self.lines_horse,self.lines_human);
            else
                if self.humanImage then
                    self.lines_human,self.training_images_human,self.training_labels_human,
                    self.lines_horse,self.training_images_horse,self.training_labels_horse=self:shuffleLinesOptimizing();
                else
                    self.lines_human,self.training_labels_human,
                    self.lines_horse,self.training_images_horse,self.training_labels_horse=self:shuffleLinesOptimizing();
                end
                -- self.lines_face,self.training_images,self.training_labels=self:shuffleLinesOptimizing(self.lines_face,self.training_images,self.training_labels);
            end
        end

    end

    function data:shuffleLinesOptimizing()
        local lines = self.lines_human;
        local y=self.lines_horse;
        local x=lines;
        local len=#lines;

        local shuffle = torch.randperm(len)
        
        local im_2;
        
        if self.humanImage then
            im_2=self.training_images_human:clone();
        end

        local labels_2=self.training_labels_human:clone();
        local im_3=self.training_images_horse:clone();
        local labels_3=self.training_labels_horse:clone();

        local lines2={};
        local lines3={};
        for idx=1,len do
            lines2[idx]=x[shuffle[idx]];
            lines3[idx]=y[shuffle[idx]];
            
            if self.humanImage then    
                im_2[idx]=self.training_images_human[shuffle[idx]];
            end
            labels_2[idx]=self.training_labels_human[shuffle[idx]];

            im_3[idx]=self.training_images_horse[shuffle[idx]];
            labels_3[idx]=self.training_labels_horse[shuffle[idx]];
        end
        
        self.training_images_horse=0;
        self.training_labels_horse=0;
        self.training_images_human=0;
        self.training_labels_human=0;
        self.lines_horse=0;
        self.lines_human=0;

        if self.humanImage then
            return lines2,im_2,labels_2,lines3,im_3,labels_3
        else
            return lines2,labels_2,lines3,im_3,labels_3
        end
    end


    function data:readDataFileNoIm(file_path)
        local file_lines = {};
        -- print (file_path);
        for line in io.lines(file_path) do 
            local start_idx, end_idx = string.find(line, ' ');
            local img_label=string.sub(line,1,start_idx-1);

            local string_temp=string.sub(line,end_idx+1,#line);
            local start_idx, end_idx = string.find(string_temp, ' ');
            local size_r=string.sub(string_temp,1,start_idx-1);
            local size_c=string.sub(string_temp,end_idx+1,#string_temp);
            file_lines[#file_lines+1]={img_label,tonumber(size_r),tonumber(size_c)};

            -- local img_label=string.sub(line,end_idx+1,#line);
            -- file_lines[#file_lines+1]={img_path,img_label};
        end 
        return file_lines
    end

    function data:readDataFile(file_path)
        local file_lines = {};
        for line in io.lines(file_path) do 
            local start_idx, end_idx = string.find(line, ' ');
            local img_path=string.sub(line,1,start_idx-1);
            local img_label=string.sub(line,end_idx+1,#line);
            file_lines[#file_lines+1]={img_path,img_label};
        end 
        return file_lines

    end


    function data:hFlipImAndLabel(im,label)
        
        -- print ('hflip');
        
        if im then
            image.hflip(im,im);
        end

        label[{{},2}]=-1*label[{{},2}]
        local temp=label[{1,{}}]:clone();
        label[{1,{}}]=label[{2,{}}]:clone()
        label[{2,{}}]=temp;

        temp=label[{4,{}}]:clone();
        label[{4,{}}]=label[{5,{}}]:clone()
        label[{5,{}}]=temp;
        -- for i=1,label:size(1) do
        --     label[i][2]=1-(label[i][2]+1)
        -- end
        
        return im,label;
    end

    function data:rotateImAndLabel(img_horse,label_horse,img_human,label_human,angles)
        
        -- print ('hflip');
        local isValid = false;
        local img_horse_org=img_horse:clone();
        local label_horse_org=label_horse:clone();

        local img_human_org=nil;
        if img_human then
            img_human_org=img_human:clone();
        end
        
        local label_human_org=label_human:clone();
        local img_human_new;

        local iter=0;
        
        while not isValid do
            isValid = true;
            label_horse= label_horse_org:clone();
            label_human= label_human_org:clone();

            local rand=math.random(#angles);
            local angle=math.rad(angles[rand]);

            local rand_human=math.random(#angles);
            local angle_human=math.rad(angles[rand_human]);
            
            img_horse=image.rotate(img_horse_org,angle,"bilinear");
            -- print ('no rotfix');
            -- local rot = torch.ones(img_horse_org:size());
            -- rot=image.rotate(rot,angle,"simple");

            -- img_horse[rot:eq(0)]=img_horse_org[rot:eq(0)];

            if img_human then
                img_human_new=image.rotate(img_human_org,angle_human,"bilinear");
            else
                img_human_new=img_human;
            end
            
            local rotation_matrix=torch.zeros(2,2);
            rotation_matrix[1][1]=math.cos(angle);
            rotation_matrix[1][2]=math.sin(angle);
            rotation_matrix[2][1]=-1*math.sin(angle);
            rotation_matrix[2][2]=math.cos(angle);
            
            local rotation_matrix_human=torch.zeros(2,2);
            rotation_matrix_human[1][1]=math.cos(angle_human);
            rotation_matrix_human[1][2]=math.sin(angle_human);
            rotation_matrix_human[2][1]=-1*math.sin(angle_human);
            rotation_matrix_human[2][2]=math.cos(angle_human);

            for i=1,label_horse:size(1) do
                if label_horse[i][3]>0 then
                    local ans = rotation_matrix*torch.Tensor({label_horse[i][2],label_horse[i][1]}):view(2,1);
                    label_horse[i][1]=ans[2][1];
                    label_horse[i][2]=ans[1][1];

                    if torch.all(label_horse[i]:ge(-1)) and torch.all(label_horse[i]:le(1)) then
                        isValid=true;
                    else
                        isValid=false;
                    end

                    ans = rotation_matrix_human*torch.Tensor({label_human[i][2],label_human[i][1]}):view(2,1);
                    label_human[i][1]=ans[2][1];
                    label_human[i][2]=ans[1][1];

                    if isValid and torch.all(label_human[i]:ge(-1)) and torch.all(label_human[i]:le(1)) then
                        isValid=true;
                    else
                        isValid=false;
                    end

                end

                if not isValid then
                    break;
                end

            end

            iter=iter+1;
            if iter==100 then
                label_horse=label_horse_org;
                img_horse=img_horse_org;
                label_human=label_human_org;
                img_human_new=img_human_org;
                break;
            end

        end        
        
        return img_horse,label_horse,img_human_new,label_human; 
    end


    function data:getBatchPoints(debug_flag)
        local horse_labels={};
        local human_labels={};
        local data_idx={};
        for idx_curr=1,self.training_set_horse.label:size(1) do
            local label_curr_horse = self.training_set_horse.label[idx_curr];
            local label_curr_human=self.training_set_human.label[idx_curr];
            -- print ('idx_curr',idx_curr);
            -- print ('label_curr_horse',label_curr_horse);
            -- print ('label_curr_human',label_curr_human);
            local keep_col=label_curr_horse[{{},3}]:gt(0)+label_curr_human[{{},3}]:gt(0)
            local idx_keep=torch.find(keep_col:gt(1):type('torch.CudaTensor'), 1)
            
            local label_curr_pos_horse=torch.zeros(#idx_keep,2):type(label_curr_horse:type());
            for idx_pos=1,#idx_keep do
                label_curr_pos_horse[idx_pos]=label_curr_horse[{idx_keep[idx_pos],{1,2}}];
            end

            local label_curr_pos_human=torch.zeros(#idx_keep,2):type(label_curr_human:type());
            for idx_pos=1,#idx_keep do
                label_curr_pos_human[idx_pos]=label_curr_human[{idx_keep[idx_pos],{1,2}}];
            end

            assert (label_curr_pos_human:size(1)==label_curr_pos_horse:size(1));
            if (label_curr_pos_human:size(1)>2) then
                horse_labels[#horse_labels+1]=label_curr_pos_horse:t();
                human_labels[#human_labels+1]=label_curr_pos_human:t();
                data_idx[#data_idx+1]=idx_curr;
            end
        end

        local data=torch.zeros(#data_idx,self.training_set_horse.data:size(2),self.training_set_horse.data:size(3),
                            self.training_set_horse.data:size(4)):type(self.training_set_horse.data:type());
        for idx_idx=1,#data_idx do
            local idx_curr=data_idx[idx_idx];
            data[idx_idx]=self.training_set_horse.data[idx_curr];
        end

        local data_human=nil;
        if self.humanImage then
            data_human=torch.zeros(#data_idx,self.training_set_human.data:size(2),self.training_set_human.data:size(3),
                                self.training_set_human.data:size(4)):type(self.training_set_human.data:type());
            for idx_idx=1,#data_idx do
                local idx_curr=data_idx[idx_idx];
                data_human[idx_idx]=self.training_set_human.data[idx_curr];
            end
            data_human=data_human:clone();
        end


        assert (#horse_labels==#human_labels)
        if debug_flag then
            return horse_labels,human_labels,data:clone(),data_human,data_idx
        else
            return horse_labels,human_labels,data:clone(),data_human
        end
    end

    function data:processImAndLabel(img_horse,img_human,label_horse,label_human,params)
        
        if not self.soumith_locnet then
            img_horse:mul(255);
            img_human:mul(255);
        end
        
        local org_size_horse=img_horse:size();
        local org_size_human=img_human:size();

        local label_horse_org=label_horse:clone();
        local label_human_org=label_human:clone();

        
        
        img_horse = image.scale(img_horse,params.input_size[1],params.input_size[2]);
        img_human = image.scale(img_human,params.input_size[1],params.input_size[2]);
        

        label_horse[{{},1}]=label_horse[{{},1}]/org_size_horse[3]*params.input_size[1];
        label_horse[{{},1}]=(label_horse[{{},1}]/params.input_size[1]*2)-1;
        label_horse[{{},2}]=label_horse[{{},2}]/org_size_horse[2]*params.input_size[2];
        label_horse[{{},2}]=(label_horse[{{},2}]/params.input_size[2]*2)-1;
        local temp = label_horse[{{},1}]:clone();
        label_horse[{{},1}]=label_horse[{{},2}]
        label_horse[{{},2}]=temp

        label_human[{{},1}]=label_human[{{},1}]/org_size_human[3]*params.input_size[1];
        label_human[{{},1}]=(label_human[{{},1}]/params.input_size[1]*2)-1;
        label_human[{{},2}]=label_human[{{},2}]/org_size_human[2]*params.input_size[2];
        label_human[{{},2}]=(label_human[{{},2}]/params.input_size[2]*2)-1;
        local temp = label_human[{{},1}]:clone();
        label_human[{{},1}]=label_human[{{},2}]
        label_human[{{},2}]=temp

        if (torch.max(label_horse)>=params.input_size[1]) then
            print ('PROBLEM horse');
            print (label_horse_org);
            print (label_horse);
            print (org_size_horse);
        end

        if (torch.max(label_human)>=params.input_size[1]) then
            print ('PROBLEM human');
            print (label_human_org);
            print (label_human);
            print (org_size_human);
        end
        
        -- flip or rotate
        if self.augmentation then
            local rand=math.random(2);
            if rand==1 then
                img_horse,label_horse = self:hFlipImAndLabel(img_horse,label_horse);
                img_human,label_human = self:hFlipImAndLabel(img_human,label_human);
            end

            img_horse,label_horse,img_human,label_human=self:rotateImAndLabel(img_horse,label_horse,img_human,label_human,params.angles);
        end

        -- subtract the mean
        if not self.soumith_locnet then
            for i=1,img_horse:size()[1] do
                img_horse[i]:csub(params.mean[i])
            end

            for i=1,img_human:size()[1] do
                img_human[i]:csub(params.mean[i])
            end
        else
            img_horse=self:soumithNormalize(img_horse);
            img_human=self:soumithNormalize(img_human);
        end


        return img_horse,img_human,label_horse,label_human

    end


    function data:addTrainingData(training_set_horse,training_set_human,batch_size,lines_horse,lines_human,start_idx_horse,params)
        
        local list_idx=start_idx_horse;
        local list_size=#lines_horse;
        
        local curr_idx=1;

        while curr_idx<= batch_size do
            
            local status_img_horse,status_img_human,img_horse,img_human;
            local img_path_horse=lines_horse[list_idx][1];
            local label_path_horse=lines_horse[list_idx][2];
            local img_path_human=lines_human[list_idx][1];
            local label_path_human=lines_human[list_idx][2];
            local label_horse,label_human;

            if self.optimize then
                status_img_horse = true;
                status_img_human = true;
                img_horse = self.training_images_horse[list_idx]:clone();
                img_human = self.training_images_human[list_idx]:clone();
                label_horse = self.training_labels_horse[list_idx];
                label_human = self.training_labels_human[list_idx];
            else
                status_img_horse,img_horse=pcall(image.load,img_path_horse);
                status_img_human,img_human=pcall(image.load,img_path_human);
            end

            if status_img_horse and status_img_human then
                if not self.optimize then
                    label_horse=npy4th.loadnpy(label_path_horse):double();
                    label_human=npy4th.loadnpy(label_path_human):double();
                end

                if img_horse:size()[1]==1 then
                    img_horse= torch.cat(img_horse,img_horse,1):cat(img_horse,1)
                end
                
                if img_human:size()[1]==1 then
                    img_human= torch.cat(img_human,img_human,1):cat(img_human,1)
                end

                img_horse,img_human,label_horse,label_human=self:processImAndLabel(img_horse,img_human,label_horse,label_human,params)

                if self.bgr then
                    local img_horse_temp=img_horse:clone();
                    img_horse[{1,{},{}}]=img_horse_temp[{3,{},{}}];
                    img_horse[{3,{},{}}]=img_horse_temp[{1,{},{}}];

                    local img_human_temp=img_human:clone();
                    img_human[{1,{},{}}]=img_human_temp[{3,{},{}}];
                    img_human[{3,{},{}}]=img_human_temp[{1,{},{}}];
                end

                training_set_horse.data[curr_idx]=img_horse:int();
                training_set_human.data[curr_idx]=img_human:int();
                
                training_set_horse.label[curr_idx]=label_horse;
                training_set_human.label[curr_idx]=label_human;
            else
                print ('PROBLEM READING INPUT');
                curr_idx=curr_idx-1;
            end
            
            list_idx=(list_idx%list_size)+1;
            curr_idx=curr_idx+1;
        end
        return list_idx;
    
    end

    function data:processImAndLabelNoIm(img_horse,org_size_human,label_horse,label_human,params)
        
        if not self.soumith_locnet then
            img_horse:mul(255);
        end
        
        local org_size_horse=img_horse:size();
        
        local label_horse_org=label_horse:clone();
        local label_human_org=label_human:clone();

        
        assert (img_horse:size(2)==params.input_size[1])
        assert (img_horse:size(3)==params.input_size[2])

        label_horse[{{},1}]=label_horse[{{},1}]/org_size_horse[3]*params.input_size[1];
        label_horse[{{},1}]=(label_horse[{{},1}]/params.input_size[1]*2)-1;
        label_horse[{{},2}]=label_horse[{{},2}]/org_size_horse[2]*params.input_size[2];
        label_horse[{{},2}]=(label_horse[{{},2}]/params.input_size[2]*2)-1;
        local temp = label_horse[{{},1}]:clone();
        label_horse[{{},1}]=label_horse[{{},2}]
        label_horse[{{},2}]=temp

        label_human[{{},1}]=label_human[{{},1}]/org_size_human[2]*params.input_size[1];
        label_human[{{},1}]=(label_human[{{},1}]/params.input_size[1]*2)-1;
        label_human[{{},2}]=label_human[{{},2}]/org_size_human[1]*params.input_size[2];
        label_human[{{},2}]=(label_human[{{},2}]/params.input_size[2]*2)-1;
        local temp = label_human[{{},1}]:clone();
        label_human[{{},1}]=label_human[{{},2}]
        label_human[{{},2}]=temp

        if (torch.max(label_horse)>=params.input_size[1]) then
            print ('PROBLEM horse');
            print (label_horse_org);
            print (label_horse);
            print (org_size_horse);
        end

        if (torch.max(label_human)>=params.input_size[1]) then
            print ('PROBLEM human');
            print (label_human_org);
            print (label_human);
            print (org_size_human);
        end
        
        -- flip or rotate
        if self.augmentation then
            local rand=math.random(2);
            
            if rand==1 then
                img_horse,label_horse = self:hFlipImAndLabel(img_horse,label_horse);
                _,label_human = self:hFlipImAndLabel(nil,label_human);
            end

            img_horse,label_horse,_,label_human=self:rotateImAndLabel(img_horse,label_horse,nil,label_human,params.angles);
        end

        -- subtract the mean
        -- print (self.soumith_locnet);
        if not self.soumith_locnet then
            for i=1,img_horse:size()[1] do
                img_horse[i]:csub(params.mean[i])
            end
        else
            -- print ('soumith_normalize');
            -- print (torch.min(img_horse),torch.max(img_horse));
            img_horse=self:soumithNormalize(img_horse);
            -- print (torch.min(img_horse),torch.max(img_horse));
        end

        return img_horse,label_horse,label_human
        
    end

    function data:soumithNormalize(img_curr)
        assert (self.soumith_std);
        assert (self.soumith_mean);
        for i=1,3 do -- channels
            img_curr[{{i},{},{}}]:add(-self.soumith_mean[i]);
            img_curr[{{i},{},{}}]:div(self.soumith_std[i]);
        end
        return img_curr
    end

    function data:addTrainingDataNoIm(training_set_horse,training_set_human,batch_size,lines_horse,lines_human,start_idx_horse,params)
        
        local list_idx=start_idx_horse;
        local list_size=#lines_horse;
        training_set_horse.files={}

        local curr_idx=1;

        while curr_idx<= batch_size do
            
            local status_img_horse,img_horse;
            local img_path_horse=lines_horse[list_idx][1];
            local label_path_horse=lines_horse[list_idx][2];
            
            local img_path_human={lines_human[list_idx][2],lines_human[list_idx][3]};
            local label_path_human=lines_human[list_idx][1];
            
            local label_horse,label_human;


            if self.optimize then
                status_img_horse = true;
                img_horse = self.training_images_horse[list_idx]:clone();
                label_horse = self.training_labels_horse[list_idx]:clone();
                label_human = self.training_labels_human[list_idx]:clone();
            else
                status_img_horse,img_horse=pcall(image.load,img_path_horse);
            end



            if status_img_horse then
                if not self.optimize then
                    label_horse=npy4th.loadnpy(label_path_horse):double();
                    label_human=npy4th.loadnpy(label_path_human):double();
                end

                if img_horse:size()[1]==1 then
                    img_horse= torch.cat(img_horse,img_horse,1):cat(img_horse,1)
                end
                
                img_horse,label_horse,label_human=self:processImAndLabelNoIm(img_horse,img_path_human,label_horse,label_human,params)
                
                if self.bgr then
                    -- print 'bgring';
                    local img_horse_temp=img_horse:clone();
                    img_horse[{1,{},{}}]=img_horse_temp[{3,{},{}}];
                    img_horse[{3,{},{}}]=img_horse_temp[{1,{},{}}];
                end

                training_set_horse.data[curr_idx]=img_horse;
                
                training_set_horse.label[curr_idx]=label_horse;
                training_set_human.label[curr_idx]=label_human;
                training_set_horse.files[#training_set_horse.files+1]=img_path_horse;
            else
                print ('PROBLEM READING INPUT');
                curr_idx=curr_idx-1;
            end
            
            list_idx=(list_idx%list_size)+1;
            curr_idx=curr_idx+1;
        end
        return list_idx;
    
    end
    
end

return data