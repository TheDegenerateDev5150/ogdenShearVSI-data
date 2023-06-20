function  [x,y,z,TRI] = genMesh(fileName,mesh,params,pres_disp,...
    mesh_ref,abaqus_ver,elementType,d,N,A,l)

fN = erase(fileName,['_' mesh]);

% Length parameters
w = d; h = d;

% Determine maximum element size
mesh_ref.maxelsize = nthroot(l*w*h*6*sqrt(2)/mesh_ref.num_of_el,3);

% Sinusoidal parameters
edge.coef{1} = -A; % Amplitude
edge.coef{3} = A;
edge.period = N; % Period

% Edge resolution
if A == 0 || N == 0
    edge.shape{1} = 'line'; edge.shape{2} = 'line'; edge.shape{3} = 'line'; edge.shape{4} = 'line';
    line_res = [4 4 4 4];
else
    edge.shape{1} = 'sin'; edge.shape{2} = 'line'; edge.shape{3} = 'sin'; edge.shape{4} = 'line';
    line_res = [round(l/mesh_ref.maxelsize)+4 4 round(l/mesh_ref.maxelsize)+4 4]; 
end
edge.func{1} = @(x) edge.coef{1}*sin(2*pi*edge.period*x/abs(l)) + w/2;
edge.func{3} = @(x) edge.coef{3}*sin(2*pi*edge.period*x/abs(l)) - w/2;

% Create the mesh given geometric parameters
model_3D = createGeometry(l,w,h,line_res,edge,mesh_ref);
x = model_3D.Mesh.Nodes(1,:)'; y = model_3D.Mesh.Nodes(2,:)'; 
z = model_3D.Mesh.Nodes(3,:)';
TRI = model_3D.Mesh.Elements';

% To view the 3D model, set breakpoint here and type the following commands
% pdeplot3D(model_3D)
% axis off

% Set the material parameters
switch params
    case 'ogden-treloar'
        coef.model = 'Og_3';
        coef.val = [0.4017 1.3 0.00295 5 0.00981 -2 0 0 0];
                      % [mu_1 a_1 mu_2 a_2 mu_3 a_3 k_1 k_2 k_3]
                      % Units are in MPa
                      % See https://solidmechanics.org/text/Chapter3_5/Chapter3_5.htm
                      % Note the correction from the original Treloar data
                      % factors. This is due to the original paper
                      % utilizing the original formulation of the Ogden
                      % model. For the Abaqus formulation, all mu_i values
                      % should be positive (https://polymerfem.com/4-things-you-didnt-know-about-the-ogden-model/).
                      % Correction factor: mu_i =a_i*mu_orig_i/2;
end

% Set all node coordinates as a matrix
Nodes.gen=[x y z];

% Identify boundary surfaces
Surf.x1 = find(and(x<=max(x)+10^-9,x>=max(x)-10^-9));
Surf.x2 = find(and(x<=min(x)+10^-9,x>=min(x)-10^-9));
Surf.z1 = find(and(z<=max(z)+10^-9,z>=max(z)-10^-9));
Surf.z2 = find(and(z<=min(z)+10^-9,z>=min(z)-10^-9));
if A == 0 || N == 0
    Surf.y1 = find(and(y<=max(y)+10^-9,y>=max(y)-10^-9));
    Surf.y2 = find(and(y<=min(y)+10^-9,y>=min(y)-10^-9));
else % For sinusoidal surfaces
    Surf.y1 = []; Surf.y2 = [];
    for j = 1:length(Nodes.gen)
        if ismembertol(y(j),edge.func{1}(x(j)))
            Surf.y1 = [Surf.y1;j];
        elseif ismembertol(y(j),edge.func{3}(x(j)))
            Surf.y2 = [Surf.y2;j];
        end
    end
end

% Declare boundary conditions (may be parameterized)
Nodes.bc1 = Surf.y1;
Nodes.bc2 = Surf.y2;
Nodes.presDisp.dir = 'x';
Nodes.presDisp.mag = pres_disp;

% Creating the element set associated with boundary conditions
idx1 = [];
for k = 1:length(Nodes.bc1)
    [row1,~] = find(TRI==Nodes.bc1(k));
    idx1 = [idx1;row1];
end
Elements_Sets{1}.bc1 = unique(idx1);

idx2 = [];
for k = 1:length(Nodes.bc2)
    [row2,~] = find(TRI==Nodes.bc2(k));
    idx2 = [idx2;row2];
end
Elements_Sets{1}.bc2 = unique(idx2);

 % Nodes indices vector for each Elements{i}
for i=1:1:size(TRI,1) 
    Elements{i}=TRI(i,:);              
end

% Element set name
Elements_Sets{1}.Name='Set-1';

% Set element type
switch mesh
    case 'tet'
        Elements_Sets{1}.Elements_Type=elementType;
end

% Elements indices vectors in the element set
Elements_Sets{1}.Elements=1:size(TRI,1);

% Organizes optimization 'sweeps' into subfolders
writeInp(Nodes,Elements,Elements_Sets,fN,coef,abaqus_ver,mesh);