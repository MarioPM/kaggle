library(readr)
library(data.table)
library(xgboost)
library(caretEnsemble)
library(reshape2)
library(dplyr)
setwd("/home/branden/Documents/kaggle/walmart")

ts1Trans <- data.table(read_csv("./data_trans/ts1Trans3_prop_simil.csv", col_types=paste(replicate(6839, "n"), collapse = "")))
# ts1_dept_simil <- data.table(read_csv("./data_trans/ts1_dept_simil_prop.csv", col_types=paste(replicate(69, "n"), collapse = "")))
# ts1_fine_simil <- data.table(read_csv("./data_trans/ts1_fine_simil_prop.csv", col_types=paste(replicate(5354, "n"), collapse = "")))

# ts1Trans[, 47:115] <- ts1_dept_simil
# ts1Trans[, 116:5469] <- ts1_fine_simil

# Create a vector the variable names to be used
varnames <- names(which(sapply(ts1Trans[filter==0, 4:ncol(ts1Trans), with=FALSE], function(x) uniqueN(x))>1))
# Create a separate train set -- This isn't necessary because I'm doing CV now instead of a single validation set 
# TSNE
# set.seed(42)
# ts1TSNE <- ts1Trans[, varnames, with=FALSE]
# ts1TSNE <- Rtsne(as.matrix(ts1Trans[, varnames, with=FALSE]), check_duplicates=FALSE, pca=FALSE, perplexity=30, theta=0.5, dims=2)

# REDOING THIS BECAUSE YOU DIDN'T DO TSNE ON THE WHOLE DATASET

# Was only necessary for easier filtering of the validation set
train <- ts1Trans[filter==0, c("class",varnames), with=FALSE]
# train <- cbind(train, ts1TSNE$Y)

# IMPORTANT -- keep the same seed so that the folds used in creating models are the same.
load("./data_trans/cvFoldsList.rda")

# dval <- xgb.DMatrix(data=data.matrix(train[cvFoldsList[[1]],varnames, with=FALSE]),label=data.matrix(train$class[cvFoldsList[[1]]]))
# dtrain <- xgb.DMatrix(data=data.matrix(train[-cvFoldsList[[1]],varnames, with=FALSE]),label=data.matrix(train$class[-cvFoldsList[[1]]]))
# watchlist <- list(train=dtrain, val=dval)

dtrain <- xgb.DMatrix(data=data.matrix(train[,varnames, with=FALSE]),label=data.matrix(train$class))

param <- list(objective="multi:softprob",
              eval_metric="mlogloss",
              num_class=38,
              eta = .05,
              max_depth=3,
              min_child_weight=1,
              subsample=1,
              colsample_bytree=1
)
# (tme <- Sys.time())
# set.seed(201510)
# xgb9 <- xgb.train(data = dtrain,
#                params = param,
#                nrounds = 5000,
#                watchlist=watchlist,
#                maximize=FALSE,
#                print.every.n = 20,
#                early.stop.round=50)
# Sys.time() - tme

set.seed(201510)
(tme <- Sys.time())
xgb9 <- xgb.cv(data = dtrain,
               params = param,
               nrounds = 5000,
               folds=cvFoldsList,
               maximize=FALSE,
               prediction=TRUE,
               print.every.n = 20,
               early.stop.round=50)
Sys.time() - tme
save(xgb9, file="./stack_models/xgb9.rda")

samp <- read.csv('sample_submission.csv')
cnames <- paste("xgb9", names(samp)[2:ncol(samp)], sep="_")
colnames(xgb9$pred) <- cnames
write.csv(data.frame(VisitNumber=ts1Trans[filter==0,"VisitNumber",with=FALSE], xgb9$pred), "./stack_models/cvPreds_xgb9.csv", row.names=FALSE) 

minLossRound <- which.min(xgb9$dt$test.mlogloss.mean)
rounds <- minLossRound * 1.15

## Create a model using the full dataset -- make predictions on test set for use in future stacking
set.seed(201510)
(tme <- Sys.time())
xgb9full <- xgb.train(data = dtrain,
                      params = param,
                      nrounds = rounds,
                      maximize=FALSE,
                      print.every.n = 20)
Sys.time() - tme
save(xgb9full, file="./stack_models/xgb9full.rda")

preds <- predict(xgb9full, data.matrix(ts1Trans[filter==2, varnames, with=FALSE]))
preds <- data.frame(t(matrix(preds, nrow=38, ncol=length(preds)/38)))
samp <- read.csv('sample_submission.csv')
cnames <- names(samp)[2:ncol(samp)]
names(preds) <- cnames
submission <- data.frame(VisitNumber=samp$VisitNumber, preds)
write.csv(submission, "./stack_models/testPreds_xgb9full.csv", row.names=FALSE)


