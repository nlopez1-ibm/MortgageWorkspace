//IBMUSERO JOB 'ACCT#',MSGCLASS=H,REGION=0M,MSGLEVEL=(1,1) 
//* An Opercmd to run the CICS newcopy or PHasein in batch 
// COMMAND 'F CICSTS61,CEMT SET PROG(EPSCMORT) PH'
// COMMAND 'F CICSTS61,CEMT SET PROG(EPSMORT) PH'
//NOP EXEC PGM=IEFBR14
//*