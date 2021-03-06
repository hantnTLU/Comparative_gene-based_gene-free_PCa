################
# Author : Thi Ngoc Ha Nguyen
# Date   : 04/10/2019
# Email  : thi-ngoc-ha.nguyen@i2bc.paris-saclay.fr
################

rm(list=ls())
set.seed(12678)

################
# Load libraries
################
library(glmnet)
library(caret)
library(precrec)
library(parallel)
library(edgeR)
library(EnsDb.Hsapiens.v79)
################
# Load list of functions 
################

################
## A) Function extracts signature
################
extractSignatureStb <- function(frame, thres){
  # Extract signature
  #
  # Args:
  #   frame : Data frame containes selected probes
  #   thres : 
  # Returns :
  #   The signature of the stable selected probes
  
  X <- data.matrix(frame[,which(!names(frame)%in% c("condition"))])

  Y <- frame$condition
  
  n <- nrow(X) 
  
  p <- ncol(X)
  
  Gene <- colnames(X) 
  
  # Perform k-fold cross validation for glmnet to find optimal value of lambda
  cvGlm <- cv.glmnet(x = X, y = Y, family = "binomial", alpha = 1, type.measure = "mse")
  
  cores <- detectCores()
  
  cl <- makeCluster(cores-2)
  
  NUM_RUNS <- 2e3
  stabsel <- function(i){
    cat("+")
    b_sort <- sort(sample(1:n,round(3*n/4)))
    out <- glmnet(X[b_sort,],Y[b_sort], family = "binomial",
                  lambda=cvGlm$lambda.1se, alpha = 1, standardize = FALSE)
  
    return(tabulate(which(out$beta[,ncol(out$beta)]!=0),p))
  }
  
  clusterEvalQ(cl, expr = c(library(glmnet)))
  clusterExport(cl,c('stabsel','frame', 'NUM_RUNS','n','glmnet','cvGlm','X','Y','p'),envir=environment())
  
  res.cum <- Reduce("+", parLapply(cl, 1:NUM_RUNS, stabsel))
  
  stopCluster(cl)
  
  prob.sel <- res.cum/NUM_RUNS
  plot(sort(prob.sel))
  
  gene.stabsel <- Gene[prob.sel >= thres]
  
  return (gene.stabsel)
}

################
## B) Function creates list kmers from a contig
################
contig2Kmer <- function(contig, N_KMER){
  # Create list of kmers
  #
  # Args:
  #   contig : String stores a contig
  #   N_KMER : Length of generated kmer
  # Returns :
  #   List of k-mers with N_KMER length that derived from contig
  
  listKmer <-c()
 
  for(i in seq(1, nchar(contig)-N_KMER+1)){
    listKmer = c(listKmer, substr(contig, i, i+N_KMER-1))
  }
  return(listKmer)
}

################
## C) Function creates reverse complement sequence
################
convertToReverComplement<-function(seq){
  # Reverse complement sequence
  #
  # Args:
  #   seq : String stores a sequence
  # Returns :
  #   A reverse complement sequence
  bases=c("A","C","G","T")
  uSeq<-unlist(strsplit(toupper(seq),NULL))
  
  complete <- lapply(uSeq,function(bbb){
    if(bbb=="A") compString<-"T"
    if(bbb=="C") compString<-"G"
    if(bbb=="G") compString<-"C"
    if(bbb=="T") compString<-"A"
    if(!bbb %in% bases) compString<-"N"
    return(compString)
  })
  return(paste(rev(unlist(complete)),collapse=""))
}

################
## D) Function to create list -kmers from list of contigs
################
fromContig2Kmers <- function(sigDiscovery, kmer_len=31, lib_type ="unstranded"){
  # Create list k-mers
  #
  # Args:
  #   sigDiscovery : List of probes
  # Returns :
  #   List of probes and list of k-mers that are derived from each probe
  
  vectorKmer = c()
  listKmer = list()
  for(i in 1:length(sigDiscovery)){
    vectorKmer <- c(vectorKmer,contig2Kmer(sigDiscovery[i], kmer_len))
    listKmer[[i]] = contig2Kmer(sigDiscovery[i], kmer_len)
  }
  
  # check revers completement
  vectorCono = c()
  for(kmer in vectorKmer){
    
    rever <-convertToReverComplement(kmer)
    
    if(lib_type == "unstranded"){
      
      # Just keep cononical kmer
      if(kmer<rever){
        vectorCono <- c(vectorCono, kmer)
      }else{
        vectorCono <- c(vectorCono, rever)
      }
      
    }else{
      vectorCono <- c(vectorCono, kmer, rever)
      
    }
    
  }
  
  listCono = list()
  for (i in 1:length(listKmer)){
    tmp = c()
    for (kmer in listKmer[[i]]){
      rever <-convertToReverComplement(kmer)
      if(lib_type =="unstranded"){
        if(kmer<rever){
          tmp = c(tmp,kmer)
        }else{
          tmp = c(tmp,rever)
        }
      }else{
        tmp <- c(tmp,kmer,rever)  
      }
      
    }
    listCono[[i]]<-tmp
  }
  names(listCono)<-sigDiscovery
  return(listCono)
}
###############
# E) Function calculater auc of signature in validation set
###############
takeDataReturnAUC<- function(frameTrain, frameTest, absentContig, status){
  # Calculate auc of signature 
  #
  # Args:
  #   frameTrain: Data frame containes selected probes in training set
  #   frameTest : Data frame containes selected probes in test set
  #   absentContig : List of absence contig in test set
  #
  # Results:
  #   AUC ROC curve in test set
  #   List coefficents for each probe in the signature
  
  data.train <- as.data.frame(frameTrain)
  
  data.test <- as.data.frame(frameTest)
  

  # Train model 
  ctrl <- trainControl(method = "repeatedcv",
                       number = 10,
                       repeats = 20,
                       classProbs = TRUE,
                       summaryFunction = twoClassSummary,
                       savePredictions = TRUE)
                      
  
  # Use glm method in caret package
  glmFit <- train(condition ~ ., data = data.train,
                    method = "glm",
                    metric = "ROC",
                    family = "binomial",
                    preProc = c("center", "scale"),
                    trControl = ctrl)  
  
  #Roc AUC for TCGA tranning dataset
  aucMeanTCGA <- round(mean(glmFit$resample$ROC), 3)
  aucSdTCGA <- round(sd(glmFit$resample$ROC), 3)
  
  # Set coefficent of absent contig =0
  if(length(absentContig)!=0){

    for (i in 1:length(absentContig)){
	  if(grepl("-", absentContig[i], fixed = TRUE)){
		absentContig[i] = paste0("`\\`", absentContig[i], "\\``")
      }
    }

    for (contig in absentContig){
      
      glmFit$finalModel$coefficients[contig] = 0
      
    }
    
  }
  
  # Predition for test data
  if(status == "risk"){
	pred = predict(glmFit, data.test[,-1, drop = FALSE], type = "prob")[, "LR"]
  }
  if(status == "relapse"){
	  pred = predict(glmFit, data.test[,-1, drop = FALSE], type = "prob")[, "No"]
  }
  
  # Calculate auc for ROC curve
  resAUC <- auc(evalmod(scores = pred, labels = data.test$condition))
  
  rocAUC <- round(resAUC$aucs[1], 3)
  
  if(rocAUC<0.5){ # Reverse roc value in case it lower than 0.5
    
    rocAUC = 1 - rocAUC
    
  }
  # Variable importance
  
  return(list(aucMeanTCGA, aucSdTCGA, rocAUC, varImp(glmFit)))
}

################
## F) Function to take gene name from gene ensembl
################
fromGeneIDtakeGenName <- function(geneEnsembl){
  # Infer gene symbol from gene ensembl 
  #
  # Args:
  #   geneEnsembel: String stores gene ensembl 
  # Results:
  #   Gene symbol
  
  geneAnno <- gsub("\\..*","",geneEnsembl)
  geneAnno <- ensembldb::select(EnsDb.Hsapiens.v79, keys= geneAnno, keytype = "GENEID", columns = c("SYMBOL","GENEID")) 
  return (geneAnno)
}
################
## G) Function to CBP normalize for kmers are found in validation set
################
normalizeContig <-function(validCountPath, libSizePath){
  # CBP normalization for kmer are found in validation set
  #
  # Args:
  #  validCountPath: Path to store validation data
  #  libSizePath: Path to store total of kmers for each sample in validation set
  # Results:
  # Dataframe store normalized kmer counts are found in validation set
	
  # Dataframe stores kmers count that are found in validation set
  countKmerValid <- as.data.frame(fread(validCountPath, sep="\t", header = TRUE))
  
  rownames(countKmerValid) <- countKmerValid$tag
  
  countKmerValid <- countKmerValid[,-1]
  
  # Dataframe, each line is a sample and its corresponding total of kmers
  inforKmerValid <- as.data.frame(fread(libSizePath, sep="\t", header = FALSE))
  names(inforKmerValid) <- c("Sample", "Total_kmers")
  rownames(inforKmerValid) <- inforKmerValid$Sample
  
  #Sort libSize base on sample name
  inforKmerValid <- inforKmerValid[colnames(countKmerValid),]
  libSizeValid <- inforKmerValid$Total_kmers
  
  # compute logCPB
  logCpbValid <- log(countKmerValid/expandAsMatrix(libSizeValid/1e+09, dim(countKmerValid))+1)
  
  return (logCpbValid)
}
