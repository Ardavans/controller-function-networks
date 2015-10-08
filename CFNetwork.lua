require 'nn'
require 'Controller'
require 'vis'

CFNetwork, parent = torch.class('nn.CFNetwork', 'nn.Module')

function CFNetwork:__init(options)
    self.controller = nn.Controller(
            options.input_dimension, -- needs to look at the whole input
            options.num_functions, -- outputs a weighting over all the functions
            options.controller_units_per_layer,
            options.controller_num_layers,
            options.controller_dropout)

    self.functions = {}
    for i = 1, options.num_functions do
        local layer = nn.Sequential()
        layer:add(nn.Linear(options.input_dimension, options.input_dimension))
        layer:add(nn.PReLU())
        table.insert(self.functions, layer)
    end

    for i = 1, #self.functions do
        print(self.functions[i])
    end

    self.mixtable = nn.MixtureTable()
end

function CFNetwork:step(input)
    local controller_output = self.controller:step(input)
    -- print("Weights:", vis.simplestr(controller_output[1]))

    local function_outputs = {}
    for i = 1, #self.functions do
        local function_output = self.functions[i]:forward(input)
        -- print("Function " .. i .. " output:", vis.simplestr(function_output[1]))
        table.insert(function_outputs, function_output)
    end

    self.output = self.mixtable:forward({controller_output, function_outputs})
    -- print("Final output:", vis.simplestr(self.output[1]))

    return self.output
end

function CFNetwork:backstep(input, gradOutput)
    local step_trace = self.controller.trace[#self.controller.trace]
    local controller_output = step_trace[#step_trace].output

    -- forward the functions to guarantee correct operation
    local function_outputs = {}
    for i = 1, #self.functions do
        table.insert(function_outputs, self.functions[i]:forward(input))
    end


    local grad_table = self.mixtable:backward(
            {controller_output, function_outputs},
            gradOutput)

    local grad_controller_output = grad_table[1]
    local grad_function_outputs = grad_table[2]
    -- print("grad_controller_output:", vis.simplestr(grad_controller_output[1]))
    -- for i = 1, #grad_function_outputs do
    --     print("grad_function_outputs for function "..i ..":", vis.simplestr(grad_function_outputs[i][1]))
    -- end

    self.gradInput = self.controller:backstep(nil, grad_controller_output):clone()

    for i = 1, #self.functions do

        self.gradInput = self.gradInput + self.functions[i]:backward(input, grad_function_outputs[i])
    end
end

function CFNetwork:backward(inputs, grad_outputs)
    for timestep = #inputs, 1, -1 do
        self:backstep(inputs[timestep], grad_outputs[timestep])
    end
end

function CFNetwork:reset(batch_size)
    batch_size = batch_size or opt.batch_size
    self.controller:reset(batch_size)
end

-- taken from nn.Container
function CFNetwork:parameters()
    local function tinsert(to, from)
        if type(from) == 'table' then
            for i=1,#from do
                tinsert(to,from[i])
            end
        else
            table.insert(to,from)
        end
    end
    local w = {}
    local gw = {}
    for i=1,#self.functions do
        local mw,mgw = self.functions[i]:parameters()
        if mw then
            tinsert(w,mw)
            tinsert(gw,mgw)
        end
    end
    local mw,mgw = self.controller:parameters()
    if mw then
        tinsert(w,mw)
        tinsert(gw,mgw)
    end
    return w,gw
end

function CFNetwork:training()
    for i = 1, #self.functions do
        self.functions[i]:training()
    end
    self.controller:training()
end

function CFNetwork:evaluate()
    for i = 1, #self.functions do
        self.functions[i]:evaluate()
    end
    self.controller:evaluate()
end