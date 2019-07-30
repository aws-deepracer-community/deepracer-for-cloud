#include "mainwindow.h"
#include "ui_mainwindow.h"

//sudo apt-get install libqt5svg5*

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow)
{
    ui->setupUi(this);
    ui->reward_plot->setTitle("Reward Graph");
    ui->reward_plot->setAxisTitle(0, "reward");
    ui->reward_plot->setAxisTitle(2, "iteration");
    this->refresh();
    ui->log->append("Log:\n");
}

MainWindow::~MainWindow()
{
    delete ui;
    delete reward_per_iteration_data;
    delete reward_per_iteration_samples;
}

void MainWindow::refresh(){
    //Update all the text with what is currently in the targeted files
    QFile reward_func_file(reward_func_path);
    if(!reward_func_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open reward function file: " + reward_func_file.errorString());
    } else {
        QTextStream in(&reward_func_file);
        current_reward_func = in.readAll();
        reward_func_file.close();
    }

    QFile action_space_file(action_space_path);
    if(!action_space_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open action space file: " + action_space_file.errorString());
    } else {
        QTextStream in(&action_space_file);
        current_action_space = in.readAll();
        action_space_file.close();
    }


    QFile hyperparameters_file(hyperparameters_path);
    if(!hyperparameters_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open hyperparameters file: " + hyperparameters_file.errorString());
    } else {
        QTextStream in(&hyperparameters_file);
        QString rl_file(in.readAll());
        QString text("Hyperparameters:\n");
        for(int i=0;i<hyperparams.length();i++){
            text += hyperparams[i] + " : ";
            int x=rl_file.indexOf(hyperparams[i])+hyperparams[i].length()+2; //Starts with + 2 because of "": #######," format
            while(rl_file.at(x) != '\n' && rl_file.at(x) != ','){
                text += rl_file.at(x);
                x++;
            }
            text += "\n";
        }
        current_hyperparameters = text;
        hyperparameters_file.close();
    }


    QFile track_file(track_path);
    if(!track_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open track file: " + track_file.errorString());
    } else {
        QTextStream in(&track_file);
        current_track = in.readLine(); //First line contains track
        track_file.close();
    }

    //Set all the text on the GUI to the updated strings
    ui->reward_function->setText(current_reward_func);
    ui->action_space->setText(current_action_space);
    ui->hyper_parameters->setText(current_hyperparameters);
    ui->track_name->setText(current_track);
}

void MainWindow::parse_logfile(){
    //Read log file and update QVector of reward per iteration
    QFile log_file(log_path);
    if(!log_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open log file: " + log_file.errorString());
    } else {
        int iteration = 0;
        double reward_per_iteration = 0;
        while(!log_file.atEnd()){
            QString line =log_file.readLine();
            QString marker = "SIM_TRACE_LOG:";
            QStringList list;
            if(line.contains(marker)){
                list = line.right(line.length()-line.indexOf(marker)-marker.length()).split(",");
                if(list[0].toInt() != iteration){
                    reward_per_iteration += list[log_format.indexOf("reward")].toDouble();
                    reward_per_iteration_vector.append(reward_per_iteration);
                    reward_per_iteration = 0;
                    iteration++;
                } else {
                    reward_per_iteration += list[log_format.indexOf("reward")].toDouble();
                }
            }
        }
    }
}

void MainWindow::on_save_button_clicked()
{
    //Save updates writen to the QText editor to the minio bucket and coach_rl python file
    //Update all the text with what is currently in the TextEdit

    QFile reward_func_file(reward_func_path);
    if(!reward_func_file.open(QIODevice::WriteOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open reward function file: " + reward_func_file.errorString());
    } else {
        QTextStream out(&reward_func_file);
        out << ui->reward_function->toPlainText();
        reward_func_file.close();
    }

    QFile action_space_file(action_space_path);
    if(!action_space_file.open(QIODevice::WriteOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open action space file: " + action_space_file.errorString());
    } else {
        QTextStream out(&action_space_file);
        out << ui->action_space->toPlainText();
        action_space_file.close();
    }


    QFile hyperparameters_file(hyperparameters_path);
    if(!hyperparameters_file.open(QIODevice::ReadWrite | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open hyperparameters file: " + hyperparameters_file.errorString());
    } else {
        //Read existing text in the file
        QTextStream in(&hyperparameters_file);
        QString rl_file = in.readAll(); //First line contains track

        //Read the new track from the GUI
        QString text(ui->hyper_parameters->toPlainText());

        //Edit the file text
        for(int i=0;i<hyperparams.length();i++){
            QString re(hyperparams[i]);
            int param_index = rl_file.indexOf(hyperparams[i])+hyperparams[i].length();
            while(rl_file[param_index] != '\n'){
                re+=rl_file[param_index];
                param_index++;
            }
            QString new_value(hyperparams[i]+"\":");
            param_index = text.indexOf(hyperparams[i])+hyperparams[i].length()+3;
            while(text[param_index] != '\n'){
                new_value+=text[param_index];
                param_index++;
            }
            if(hyperparams[i] != "term_cond_avg_score"){
                new_value += ",";
            }
            rl_file.replace(re,new_value);
        }

        //Write edited text back into file
        QTextStream out(&hyperparameters_file);
        hyperparameters_file.resize(0); //clear the existing file
        out << rl_file; //First line contains new track name
        hyperparameters_file.close();
    }


    QFile track_file(track_path);
    if(!track_file.open(QIODevice::ReadWrite | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open track file: " + track_file.errorString());
    } else {
        //Read existing text in the file
        QTextStream in(&track_file);
        QString env_file = in.readAll(); //First line contains track

        //Read the new track from the GUI
        QString replacementText(ui->track_name->text());

        //Edit the file text
        QString first_line = "";
        int i = 0;
        while(env_file[i] !='\n'){
            first_line += env_file[i];
            i++;
        }
        QRegularExpression re(first_line);
        env_file.replace(re, replacementText);

        //Write edited text back into file
        QTextStream out(&track_file);
        track_file.resize(0); //clear the existing file
        out << env_file; //First line contains new track name
        track_file.close();
    }

}

void MainWindow::on_start_button_clicked()
{
    //Start the simulation and training instance
    if (!QProcess::startDetached("/bin/sh", QStringList{start_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script start.sh");
    }
    ui->log->append("Starting training...");
    if(!has_memory_manager){
        //int e = system("gnome-terminal");
        //qDebug() << e;
        //ui->log->append("In order to run the memory manager copy and paste the following into a terminal: sudo python ../scripts/training/memoryManager.py");
        ui->log->append("In order to run the memory manager enter your password into the opened terminal window!");
        has_memory_manager = true;
    }
    //Access log file forupdating the graph
    QFile latest_log_file(log_path);
    if(!latest_log_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open latest log file: " + latest_log_file.errorString());
        //Have user enter a file manually as backup
        log_path = QFileDialog::getOpenFileName(this,"Open the most recently created log file.");
        ui->log->append("Reading " + log_path);
    } else {
        ui->log->append("Reading latest log file");
    }
}

void MainWindow::on_restart_button_clicked()
{
    //Restart the simulation and training instance using model that has been training (ie using pretrained model)
    //This allows you to tweak the parameters incrementally
    if (!QProcess::startDetached("/bin/sh", QStringList{stop_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script start.sh");
    }
    if (!QProcess::startDetached("/bin/sh", QStringList{use_pretrained_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script set-last-run-to-pretrained.sh");
    }
    if (!QProcess::startDetached("/bin/sh", QStringList{start_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script start.sh");
    }
    ui->log->append("Restarting...");
}

void MainWindow::on_stop_button_clicked()
{
    //Stop the training instance
    //Stop the simulation and training instance
    if (!QProcess::startDetached("/bin/sh", QStringList{stop_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script stop.sh");
    }
    ui->log->append("Stopping training...");

}

void MainWindow::on_init_button_clicked()
{
    //Init the Repository, this also can perform recovery if something brakes
    if (!QProcess::startDetached("/bin/sh", QStringList{init_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script init.sh");
    }
    ui->log->append("Wait while the init script runs; this may take a minute or two. Once the init script finishes you may run refresh to see reward function, action space, and hyperparameters.");
}

void MainWindow::on_uploadbutton_clicked()
{
    //Upload snapshot to S3, make sure envs are set
    if (!QProcess::startDetached("/bin/sh", QStringList{upload_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script upload-snapshot.sh");
    }
    ui->log->append("Uploading model to S3...");
}

void MainWindow::on_delete_button_clicked()
{
    //Delete last model
    if (!QProcess::startDetached("/bin/sh", QStringList{delete_script})){
        QMessageBox::warning(this, "Warning", "Failed to run script delete-last-run.sh");
    }
    ui->log->append("Deleting last model...");
}

void MainWindow::on_refresh_button_clicked()
{
    this->refresh();

    parse_logfile();
    for(int i=0;i<reward_per_iteration_vector.length();i++){
        reward_per_iteration_samples->push_back(QPointF(i, reward_per_iteration_vector[i]));
    }
    reward_per_iteration_data->setSamples(*reward_per_iteration_samples);
    reward_per_iteration.setData(reward_per_iteration_data);
    reward_per_iteration.attach(ui->reward_plot);
    ui->reward_plot->replot();

    ui->log->append("GUI Refreshed.");
}
