package TestsMainTest;
    import StmtFSM :: *;
    import TestHelper :: *;

    import PA200T :: *;

    (* synthesize *)
    module [Module] mkTestsMainTest(TestHelper::TestHandler);

        PA200T dut <- mkPA200T();




        Stmt s = {
            seq
                $display("Hello World from the testbench.");

            endseq
        };
        FSM testFSM <- mkFSM(s);



        method Action go();
            testFSM.start();
        endmethod

        method Bool done();
            return testFSM.done();
        endmethod
    endmodule

endpackage
