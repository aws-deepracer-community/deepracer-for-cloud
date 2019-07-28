#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>

#include <QFile>
#include <QTextStream>
#include <QMessageBox>
#include <QtDebug>

namespace Ui {
class MainWindow;
}

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = 0);
    ~MainWindow();

private slots:
    void on_start_button_clicked();

    void on_save_button_clicked();

    void on_restart_button_clicked();

    void on_stop_button_clicked();

private:
    Ui::MainWindow *ui;

    //File paths for all the files that will be manipulated
    QString reward_func_path=  "../docker/volumes/minio/bucket/custom_files/reward.py";
    QString action_space_path=  "../docker/volumes/minio/bucket/custom_files/model_metadata.json";
    QString hyperparameters_path=  "../rl_deepracer_coach_robomaker.py";
    QString track_path= "../docker/.env";

    //Will be read in on application start
    QString current_reward_func = "";
    QString current_action_space = "";
    QString current_hyperparameters = "";
    QString current_track = "";

    //General status variables
    bool is_running = false;
    bool is_pretrained = false;
};

#endif // MAINWINDOW_H
